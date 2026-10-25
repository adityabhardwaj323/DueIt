// supabase/functions/send-fcm-notification/fcm_v1.ts
// Pure Deno / Web Crypto implementation of Google OAuth2 Service Account & FCM HTTP v1

export interface ServiceAccount {
  project_id: string;
  private_key: string;
  client_email: string;
}

export interface FcmMessagePayload {
  title: string;
  body: string;
  data: Record<string, string>;
}

export interface FcmSendResult {
  token: string;
  success: boolean;
  unregistered?: boolean;
  error?: string;
}

// Convert Base64URL string
function base64UrlEncode(data: Uint8Array | string): string {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : data;
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

// Parse PEM PKCS8 RSA private key into CryptoKey
async function importRsaPrivateKey(pemKey: string): Promise<CryptoKey> {
  const cleanPem = pemKey
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/[\r\n\s]/g, '');

  const binaryString = atob(cleanPem);
  const keyBytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    keyBytes[i] = binaryString.charCodeAt(i);
  }

  return await crypto.subtle.importKey(
    'pkcs8',
    keyBytes.buffer,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign']
  );
}

// Sign an OAuth2 assertion JWT
export async function createGoogleSignedJwt(sa: ServiceAccount): Promise<string> {
  const header = {
    alg: 'RS256',
    typ: 'JWT',
  };

  const nowSec = Math.floor(Date.now() / 1000);
  const payload = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: nowSec + 3600,
    iat: nowSec,
  };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;

  const cryptoKey = await importRsaPrivateKey(sa.private_key);
  const signatureBytes = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signingInput)
  );

  const encodedSignature = base64UrlEncode(new Uint8Array(signatureBytes));
  return `${signingInput}.${encodedSignature}`;
}

// Exchange signed assertion JWT for Google access token
export async function getGoogleAccessToken(sa: ServiceAccount, timeoutMs = 10000): Promise<string> {
  const assertion = await createGoogleSignedJwt(sa);

  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion,
  });

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body.toString(),
      signal: controller.signal,
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`OAuth token exchange failed [${res.status}]: ${errText}`);
    }

    const data = await res.json();
    return data.access_token;
  } finally {
    clearTimeout(timeoutId);
  }
}

// Send single FCM HTTP v1 notification
export async function sendFcmHttpV1(
  projectId: string,
  accessToken: string,
  token: string,
  payload: FcmMessagePayload,
  timeoutMs = 15000
): Promise<FcmSendResult> {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const body = {
    message: {
      token: token,
      notification: {
        title: payload.title,
        body: payload.body,
      },
      data: payload.data,
    },
  };

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    if (res.ok) {
      return { token, success: true };
    }

    const errorJson = await res.json().catch(() => ({}));
    const errorCode = errorJson?.error?.details?.[0]?.errorCode || errorJson?.error?.status || '';

    // UNREGISTERED or INVALID_ARGUMENT (invalid token) means token should be deleted
    const isUnregistered = 
      res.status === 404 ||
      errorCode === 'UNREGISTERED' ||
      errorCode === 'INVALID_ARGUMENT' ||
      errorJson?.error?.message?.includes('not a valid FCM registration token');

    return {
      token,
      success: false,
      unregistered: isUnregistered,
      error: errorJson?.error?.message || `HTTP ${res.status}`,
    };
  } catch (err: any) {
    return {
      token,
      success: false,
      unregistered: false,
      error: err.name === 'AbortError' ? 'FCM request timed out' : String(err),
    };
  } finally {
    clearTimeout(timeoutId);
  }
}
