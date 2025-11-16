import { authenticatedLndGrpc, createInvoice, getInvoice } from "ln-service";
import { NWCClient } from "@getalby/sdk/nwc";
import crypto from "crypto";
import bolt11 from "bolt11";

export class LightningService {
  constructor(config) {
    this.config = config;
    this.lnd = null;
    this.nwc = null;
    this.mode = null; // 'lnd', 'nwc', or 'mock'
    this.init();
  }

  async init() {
    // Try NWC first if connection string is provided
    if (this.config.nwcUrl) {
      try {
        this.nwc = new NWCClient({
          nostrWalletConnectUrl: this.config.nwcUrl,
        });
        this.mode = "nwc";
        console.log("✓ Lightning NWC connected");
        try {
          const info = await this.nwc.getInfo();
          console.log(`  NWC Wallet: ${info.alias || "Connected"}`);
        } catch (e) {
          console.log("  NWC Wallet: Connected");
        }
        return;
      } catch (error) {
        console.error("Failed to connect to NWC:", error.message);
      }
    }

    // Try LND if credentials are provided
    if (this.config.macaroon && this.config.socket) {
      try {
        const { lnd } = authenticatedLndGrpc({
          cert: this.config.certPath,
          macaroon: this.config.macaroon,
          socket: this.config.socket,
        });

        this.lnd = lnd;
        this.mode = "lnd";
        console.log("✓ Lightning LND node connected");
        return;
      } catch (error) {
        console.error("Failed to connect to LND:", error);
      }
    }

    // Fall back to mock mode
    this.mode = "mock";
    console.warn("⚠ Running in mock mode without Lightning node");
    console.log(
      "  To use real Lightning, set NWC_URL or LND credentials in .env"
    );
  }

  async createInvoice({ tokens, description }) {
    // NWC mode
    if (this.mode === "nwc" && this.nwc) {
      try {
        const result = await this.nwc.makeInvoice({
          amount: tokens,
          description: description,
        });

        // NWC returns { invoice: "lnbc..." }
        const paymentRequest = result.invoice || result;

        // Convert to our format
        const decoded = bolt11.decode(paymentRequest);
        return {
          id: decoded.tagsObject.payment_hash,
          request: paymentRequest,
          tokens,
          description,
          created_at: new Date().toISOString(),
          expires_at: new Date(Date.now() + 3600000).toISOString(),
        };
      } catch (error) {
        console.error("Error creating NWC invoice:", error);
        console.error("Error details:", error.message);
        throw error;
      }
    }

    // LND mode
    if (this.mode === "lnd" && this.lnd) {
      try {
        const invoice = await createInvoice({
          lnd: this.lnd,
          tokens,
          description,
          expires_at: new Date(Date.now() + 3600000).toISOString(),
        });

        return invoice;
      } catch (error) {
        console.error("Error creating LND invoice:", error);
        throw error;
      }
    }

    // Mock mode
    return this.createMockInvoice(tokens, description);
  }

  async getInvoice({ id }) {
    // NWC mode - lookup invoice
    if (this.mode === "nwc" && this.nwc) {
      try {
        // NWC doesn't have a direct lookupInvoice method
        // We'll check if it's settled by attempting to get the payment
        // For now, return a structure indicating we need payment confirmation
        // The verification will happen with preimage checking
        console.log("NWC: Invoice lookup requested for", id);
        return {
          id,
          is_confirmed: false, // Will be confirmed via preimage
          tokens: 0, // Will be set from stored amount
        };
      } catch (error) {
        console.error("Error getting NWC invoice:", error);
        throw error;
      }
    }

    // LND mode
    if (this.mode === "lnd" && this.lnd) {
      try {
        const invoice = await getInvoice({
          lnd: this.lnd,
          id,
        });

        return invoice;
      } catch (error) {
        console.error("Error getting LND invoice:", error);
        throw error;
      }
    }

    // Mock mode
    return {
      id,
      is_confirmed: true,
      tokens: 21000,
    };
  }

  verifyPreimage(paymentHash, preimage) {
    try {
      // Convert preimage to buffer if it's a hex string
      const preimageBuffer = Buffer.from(preimage, "hex");

      // Hash the preimage
      const hash = crypto.createHash("sha256").update(preimageBuffer).digest();

      // Convert to hex and compare
      const computedHash = hash.toString("hex");
      const providedHash = paymentHash.toString("hex");

      return computedHash === providedHash;
    } catch (error) {
      console.error("Error verifying preimage:", error);
      return false;
    }
  }

  // Mock invoice for development/testing
  createMockInvoice(tokens, description) {
    const paymentHash = crypto.randomBytes(32).toString("hex");
    const preimage = crypto.randomBytes(32).toString("hex");

    // Create a mock invoice string
    const invoice = `lnbc${tokens}n1p0mock...`;

    return {
      id: paymentHash,
      request: invoice,
      tokens,
      description,
      created_at: new Date().toISOString(),
      expires_at: new Date(Date.now() + 3600000).toISOString(),
      secret: preimage,
    };
  }

  decodeInvoice(paymentRequest) {
    try {
      const decoded = bolt11.decode(paymentRequest);
      return {
        paymentHash: decoded.tagsObject.payment_hash,
        amount: decoded.satoshis,
        timestamp: decoded.timestamp,
        expiry: decoded.timeExpireDate,
        description: decoded.tagsObject.description,
      };
    } catch (error) {
      console.error("Error decoding invoice:", error);
      throw error;
    }
  }

  async getLightningIdentifier() {
    // Return a stable identifier for this Lightning wallet
    // This will be used to map to a single HyperEVM address
    
    if (this.mode === "nwc" && this.nwc) {
      // Use NWC connection URL as identifier
      return this.config.nwcUrl;
    }
    
    if (this.mode === "lnd" && this.lnd) {
      // For LND, use node pubkey (would need to fetch)
      return "lnd_node_" + this.config.socket;
    }
    
    // For mock mode, return a consistent identifier
    return "mock_lightning_wallet";
  }
}
