import sqlite3 from "sqlite3";
import { promisify } from "util";

export class DatabaseService {
  constructor(dbPath) {
    this.dbPath = dbPath;
    this.db = null;
  }

  async init() {
    return new Promise((resolve, reject) => {
      this.db = new sqlite3.Database(this.dbPath, (err) => {
        if (err) {
          console.error("Failed to open database:", err);
          reject(err);
          return;
        }

        console.log("✓ Database connected");
        this.createTables().then(resolve).catch(reject);
      });
    });
  }

  async createTables() {
    const run = promisify(this.db.run.bind(this.db));

    await run(`
            CREATE TABLE IF NOT EXISTS deposits (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                payment_hash TEXT UNIQUE,
                amount INTEGER NOT NULL,
                invoice TEXT,
                preimage TEXT,
                status TEXT DEFAULT 'pending',
                hyperevm_address TEXT,
                lsat_amount REAL,
                ubtc_amount REAL,
                vault_shares REAL,
                bridge_tx_hash TEXT,
                swap_tx_hash TEXT,
                deposit_tx_hash TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                paid_at DATETIME,
                completed_at DATETIME
            )
        `);

    await run(`
            CREATE TABLE IF NOT EXISTS user_wallets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                lightning_identifier TEXT UNIQUE,
                hyperevm_address TEXT UNIQUE,
                encrypted_private_key TEXT,
                lightning_address TEXT,
                nostr_pubkey TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                last_deposit_at DATETIME
            )
        `);

    await run(`
            CREATE INDEX IF NOT EXISTS idx_deposits_payment_hash 
            ON deposits(payment_hash)
        `);

    await run(`
            CREATE INDEX IF NOT EXISTS idx_deposits_hyperevm_address 
            ON deposits(hyperevm_address)
        `);

    console.log("✓ Database tables created");
  }

  async createDeposit(data) {
    const run = promisify(this.db.run.bind(this.db));

    // If hyperevm_address is provided during creation
    if (data.hyperevmAddress) {
      await run(
        `
              INSERT INTO deposits (payment_hash, amount, invoice, status, hyperevm_address)
              VALUES (?, ?, ?, ?, ?)
          `,
        [
          data.paymentHash,
          data.amount,
          data.invoice,
          data.status,
          data.hyperevmAddress,
        ]
      );
    } else {
      await run(
        `
              INSERT INTO deposits (payment_hash, amount, invoice, status)
              VALUES (?, ?, ?, ?)
          `,
        [data.paymentHash, data.amount, data.invoice, data.status]
      );
    }

    return data.paymentHash;
  }

  async updateDeposit(paymentHash, data) {
    const run = promisify(this.db.run.bind(this.db));

    const fields = [];
    const values = [];

    for (const [key, value] of Object.entries(data)) {
      if (value !== undefined) {
        // Convert camelCase to snake_case
        const snakeKey = key.replace(
          /[A-Z]/g,
          (letter) => `_${letter.toLowerCase()}`
        );
        fields.push(`${snakeKey} = ?`);
        values.push(value);
      }
    }

    if (fields.length === 0) return;

    values.push(paymentHash);

    await run(
      `
            UPDATE deposits 
            SET ${fields.join(", ")}
            WHERE payment_hash = ?
        `,
      values
    );
  }

  async getDeposit(paymentHash) {
    const get = promisify(this.db.get.bind(this.db));

    return await get(
      `
            SELECT * FROM deposits
            WHERE payment_hash = ?
        `,
      [paymentHash]
    );
  }

  async getDepositsByAddress(address) {
    const all = promisify(this.db.all.bind(this.db));

    return await all(
      `
            SELECT * FROM deposits
            WHERE hyperevm_address = ?
            ORDER BY created_at DESC
        `,
      [address]
    );
  }

  async getAllDeposits() {
    const all = promisify(this.db.all.bind(this.db));

    return await all(`
            SELECT * FROM deposits
            ORDER BY created_at DESC
        `);
  }

  async getDepositStats() {
    const get = promisify(this.db.get.bind(this.db));

    return await get(`
            SELECT 
                COUNT(*) as total_deposits,
                SUM(amount) as total_sats,
                SUM(CASE WHEN status = 'completed' THEN amount ELSE 0 END) as completed_sats,
                SUM(vault_shares) as total_shares
            FROM deposits
        `);
  }

  async getUserWallet(lightningIdentifier) {
    const get = promisify(this.db.get.bind(this.db));

    return await get(
      `
            SELECT * FROM user_wallets
            WHERE lightning_identifier = ?
        `,
      [lightningIdentifier]
    );
  }

  async createUserWallet(data) {
    const run = promisify(this.db.run.bind(this.db));

    await run(
      `
            INSERT INTO user_wallets (
                lightning_identifier, 
                hyperevm_address, 
                encrypted_private_key,
                lightning_address,
                nostr_pubkey
            )
            VALUES (?, ?, ?, ?, ?)
        `,
      [
        data.lightningIdentifier,
        data.hyperevmAddress,
        data.encryptedPrivateKey || null,
        data.lightningAddress || null,
        data.nostrPubkey || null,
      ]
    );

    return data.hyperevmAddress;
  }

  async updateUserWalletLastDeposit(lightningIdentifier) {
    const run = promisify(this.db.run.bind(this.db));

    await run(
      `
            UPDATE user_wallets
            SET last_deposit_at = CURRENT_TIMESTAMP
            WHERE lightning_identifier = ?
        `,
      [lightningIdentifier]
    );
  }

  async close() {
    return new Promise((resolve, reject) => {
      if (this.db) {
        this.db.close((err) => {
          if (err) {
            reject(err);
          } else {
            console.log("Database closed");
            resolve();
          }
        });
      } else {
        resolve();
      }
    });
  }
}
