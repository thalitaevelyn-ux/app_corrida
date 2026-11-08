import { timingSafeEqual } from "node:crypto";

/** Quem está chamando o servidor. */
export interface Caller {
  uid: string;
  email?: string;
  admin: boolean;
}

export interface Authenticator {
  /** Valida o token do header Authorization. Devolve null se inválido. */
  verify(token: string): Promise<Caller | null>;
  /** true = contas reais (Firebase); false = modo legado com APP_TOKEN. */
  readonly accounts: boolean;
}

/** Modo legado (sem Firebase): um token compartilhado, sem contas. */
export class AppTokenAuthenticator implements Authenticator {
  readonly accounts = false;
  constructor(private readonly appToken: string) {}

  async verify(token: string): Promise<Caller | null> {
    if (!this.appToken) return { uid: "local", admin: true }; // dev local sem token
    const a = Buffer.from(token),
      b = Buffer.from(this.appToken);
    if (a.length !== b.length || !timingSafeEqual(a, b)) return null;
    return { uid: "app-token", admin: false };
  }
}

/** Interface mínima do firebase-admin/auth, para testar sem Firebase. */
export interface IdTokenVerifier {
  verifyIdToken(token: string): Promise<{ uid: string; email?: string; email_verified?: boolean }>;
}

/** Contas reais: valida o ID token do Firebase. Admin = e-mail verificado em ADMIN_EMAILS. */
export class FirebaseAuthenticator implements Authenticator {
  readonly accounts = true;
  private readonly admins: Set<string>;

  constructor(
    private readonly verifier: IdTokenVerifier,
    adminEmails: string,
  ) {
    this.admins = new Set(
      adminEmails
        .split(",")
        .map((e) => e.trim().toLowerCase())
        .filter(Boolean),
    );
  }

  async verify(token: string): Promise<Caller | null> {
    if (!token) return null;
    try {
      const t = await this.verifier.verifyIdToken(token);
      const email = t.email?.toLowerCase();
      return { uid: t.uid, email, admin: !!email && !!t.email_verified && this.admins.has(email) };
    } catch {
      return null;
    }
  }
}
