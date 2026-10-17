// Source: https://github.com/openwrt/openwrt
// Versions: 1
/**
 * # Cryptographic Key and Certificate Generation
 *
 * The `pkgen` module provides mbedtls-backed private key generation, X.509
 * certificate construction, PKCS#12 bundle assembly, and PEM/DER serialisation
 * for ucode scripts.
 *
 * Typical flow: generate or load a key, build a certificate, sign it, and
 * optionally assemble a PKCS#12 bundle for distribution:
 *
 *   ```javascript
 *   import * as pk from 'pkgen';
 *
 *   // Generate a self-signed CA
 *   const caKey  = pk.generate_key({ type: 'ec', curve: 'secp256r1' });
 *   const caCert = pk.generate_cert({
 *     subject_name: 'CN=My CA',
 *     subject_key:  caKey,
 *     issuer_name:  'CN=My CA',
 *     issuer_key:   caKey,
 *     validity:     ['20240101000000', '21001231235959'],
 *     serial: 1, ca: true,
 *     key_usage: ['key_cert_sign'],
 *   });
 *   const caPem = caCert.pem();   // signing happens here
 *
 *   // Issue a leaf cert
 *   const leafKey  = pk.generate_key({ type: 'rsa', size: 2048 });
 *   const leafCert = pk.generate_cert({
 *     subject_name: 'CN=client',
 *     subject_key:  leafKey,
 *     issuer_name:  'CN=My CA',
 *     issuer_key:   caKey,
 *     validity:     ['20240101000000', '20341231235959'],
 *     serial: 2,
 *     key_usage:     ['digital_signature', 'key_encipherment'],
 *     ext_key_usage: ['client_auth'],
 *   });
 *
 *   // Assemble PKCS#12
 *   const p12 = pk.generate_pkcs12({
 *     password: 's3cr3t',
 *     cert:     leafCert.pem(),
 *     key:      leafKey,
 *     extra:    [caPem],
 *   });
 *   // write p12 (binary string) to a .p12 file
 *   ```
 *
 * All functions return `null` on failure. Use
 * {@link module:pkgen#error|error()} for a human-readable description and
 * {@link module:pkgen#errno|errno()} for the raw mbedtls error code.
 *
 * @module pkgen
 */

/**
 * Private or public key handle returned by
 * {@link module:pkgen#generate_key|generate_key()} or
 * {@link module:pkgen#load_key|load_key()}.
 *
 * @typedef {{
 *   pem: function(?boolean): ?string,
 *   der: function(?boolean): ?string
 * }} PkgenKey
 */

/**
 * Unsigned certificate handle returned by
 * {@link module:pkgen#generate_cert|generate_cert()}.
 *
 * The certificate is not signed until {@link module:pkgen.crt#pem|pem()} or
 * {@link module:pkgen.crt#der|der()} is called.
 *
 * @typedef {{
 *   pem: function(): ?string,
 *   der: function(): ?string
 * }} PkgenCert
 */

/**
 * Certificate metadata entry returned by
 * {@link module:pkgen#cert_info|cert_info()}.
 *
 * @typedef {{
 *   version:    int,
 *   issuer:     string,
 *   subject:    string,
 *   valid_from: string,
 *   valid_to:   string,
 *   serial:     string
 * }} PkgenCertInfo
 */

/**
 * Return the last mbedtls error code.
 *
 * Returns a negative mbedtls error code, `0` if no error occurred, or `-1`
 * if the last failure was due to an invalid argument (checked before mbedtls
 * was called).
 *
 * @function module:pkgen#errno
 *
 * @returns {int}
 *
 * @example
 * const key = pk.generate_key({ type: 'rsa', size: 512 });
 * if (!key)
 *   printf('error code: %d\n', pk.errno());
 */
export function errno() {};

/**
 * Return a human-readable description of the last error.
 *
 * Translates the value of {@link module:pkgen#errno|errno()} via
 * `mbedtls_strerror`. Returns `"Invalid arguments"` when `errno()` is `-1`.
 *
 * @function module:pkgen#error
 *
 * @returns {string}
 *
 * @example
 * const key = pk.generate_key({ type: 'rsa', size: 512 });
 * if (!key)
 *   die(`Key generation failed: ${pk.error()}\n`);
 */
export function error() {};

/**
 * Generate a new private key using OS entropy.
 *
 * For RSA, calls `mbedtls_rsa_gen_key`. For EC, calls `mbedtls_ecp_gen_key`.
 * Entropy is read from `getrandom(2)` (Linux) or `/dev/urandom` (other).
 *
 * Returns the key handle on success.
 *
 * Returns `null` on failure. Call {@link module:pkgen#error|error()} for
 * details.
 *
 * @function module:pkgen#generate_key
 *
 * @param {Object} opts
 * Key generation options:
 * - `type` {string} **(required)** — `"rsa"` or `"ec"`
 * - `size` {int} (RSA only, default `2048`) — key length in bits
 * - `exponent` {int} (RSA only, default `65537`) — RSA public exponent
 * - `curve` {string} (EC only, default `"secp256r1"`) — elliptic curve name
 *   recognized by mbedtls, e.g. `"secp521r1"`, `"secp384r1"`,
 *   `"secp256r1"`, `"secp256k1"`, `"secp224r1"`, `"secp192r1"`
 *
 * @returns {?PkgenKey}
 *
 * @example
 * // EC key (fast, small output)
 * const ecKey = pk.generate_key({ type: 'ec', curve: 'secp256r1' });
 *
 * // RSA key
 * const rsaKey = pk.generate_key({ type: 'rsa', size: 4096 });
 *
 * // Export the public key in PEM format
 * print(ecKey.pem(true));
 */
export function generate_key(opts) {};

/**
 * Parse a PEM-encoded private or public key.
 *
 * Calls `mbedtls_pk_parse_key` or `mbedtls_pk_parse_public_key` and
 * returns a key handle that can be used with
 * {@link module:pkgen#generate_cert|generate_cert()} or
 * {@link module:pkgen#generate_pkcs12|generate_pkcs12()}.
 *
 * Returns the key handle on success.
 *
 * Returns `null` on parse failure.
 *
 * @function module:pkgen#load_key
 *
 * @param {string} keystr
 * PEM-encoded key material (private by default; public when `pub` is true).
 *
 * @param {boolean} [pub=false]
 * When truthy, parse as a public key.
 *
 * @param {string} [passwd]
 * Passphrase for an encrypted private key (ignored when `pub` is truthy).
 *
 * @returns {?PkgenKey}
 *
 * @example
 * import * as fs from 'fs';
 *
 * const pem = fs.readfile('/etc/ssl/private/ca.key');
 * const caKey = pk.load_key(pem);
 *
 * // Load an encrypted key
 * const encKey = pk.load_key(encryptedPem, false, 'passphrase123');
 */
export function load_key(keystr, pub, passwd) {};

/**
 * Parse a PEM certificate or chain and return metadata.
 *
 * Returns an array of info objects — one per certificate in the chain.
 *
 * Returns `null` if `certstr` is not a string or parsing fails.
 *
 * **Note:** due to a bug in the current source, the `subject` field is
 * populated from the issuer DN rather than the subject DN. Both `issuer`
 * and `subject` will contain the issuer's DN.
 *
 * @function module:pkgen#cert_info
 *
 * @param {string} certstr
 * PEM-encoded certificate or chain.
 *
 * @returns {?PkgenCertInfo[]}
 *
 * @example
 * const infos = pk.cert_info(caPem);
 * printf('Issuer: %s\n', infos[0].issuer);
 * printf('Valid until: %s\n', infos[0].valid_to);
 *
 * // Parse a chain (e.g. to inspect the last cert's serial)
 * const chain = pk.cert_info(chainPem);
 * printf('Leaf serial: %s\n', chain[0].serial);
 */
export function cert_info(certstr) {};

/**
 * Build an X.509 v3 certificate.
 *
 * Prepares a certificate write context using mbedtls. The certificate is
 * **not yet signed** when this function returns — signing occurs when
 * {@link module:pkgen.crt#pem|crt.pem()} or
 * {@link module:pkgen.crt#der|crt.der()} is called.
 *
 * SubjectKeyIdentifier and AuthorityKeyIdentifier extensions are always
 * set. The digest algorithm is SHA-256.
 *
 * Returns the certificate handle on success.
 *
 * Returns `null` if any required field is missing or invalid.
 *
 * @function module:pkgen#generate_cert
 *
 * @param {Object} opts
 * Certificate options:
 * - `subject_name` {string} **(required)** — subject distinguished name in
 *   mbedtls string format, e.g. `"CN=client,O=ACME,C=US"`.
 * - `subject_key` {PkgenKey} **(required)** — key whose public part becomes
 *   the SubjectPublicKeyInfo field.
 * - `issuer_name` {string} **(required)** — issuer DN. Use the same value
 *   as `subject_name` for a self-signed certificate.
 * - `issuer_key` {PkgenKey} **(required)** — key used to sign the
 *   certificate. Use the same key as `subject_key` for self-signed.
 * - `validity` {string[]} **(required)** — two-element array
 *   `[valid_from, valid_to]`, each in `"YYYYMMDDHHmmss"` format (14
 *   digits, no separators), e.g. `"20240101000000"`.
 * - `serial` {int} (default `1`) — certificate serial number.
 * - `version` {int} (default `3`) — X.509 version (1, 2, or 3).
 * - `ca` {boolean} (default `false`) — if `true`, sets the BasicConstraints
 *   cA flag, making this a CA certificate.
 * - `max_pathlen` {int} — BasicConstraints `pathLenConstraint`. Defaults to
 *   `-1` (unlimited) when `ca` is `true`, `0` when `ca` is `false`.
 * - `key_usage` {string[]} — KeyUsage extension. Values: `"digital_signature"`,
 *   `"non_repudiation"`, `"key_encipherment"`, `"data_encipherment"`,
 *   `"key_agreement"`, `"key_cert_sign"`, `"crl_sign"`.
 * - `ext_key_usage` {string[]} — ExtendedKeyUsage extension (mbedtls ≥ 3
 *   only). Values: `"server_auth"`, `"client_auth"`, `"code_signing"`,
 *   `"email_protection"`, `"time_stamping"`, `"ocsp_signing"`, `"any"`.
 *
 * @returns {?PkgenCert}
 *
 * @example
 * // Self-signed CA
 * const caKey  = pk.generate_key({ type: 'ec', curve: 'secp256r1' });
 * const caCert = pk.generate_cert({
 *   subject_name: 'CN=My CA,O=ACME',
 *   subject_key:  caKey,
 *   issuer_name:  'CN=My CA,O=ACME',
 *   issuer_key:   caKey,
 *   validity:     ['20240101000000', '21001231235959'],
 *   serial: 1,
 *   ca: true,
 *   key_usage: ['key_cert_sign', 'crl_sign'],
 * });
 * const caPem = caCert.pem();
 *
 * // TLS server leaf cert
 * const srvKey  = pk.generate_key({ type: 'rsa', size: 2048 });
 * const srvCert = pk.generate_cert({
 *   subject_name:  'CN=example.com',
 *   subject_key:   srvKey,
 *   issuer_name:   'CN=My CA,O=ACME',
 *   issuer_key:    caKey,
 *   validity:      ['20240101000000', '20260101000000'],
 *   serial: 2,
 *   key_usage:     ['digital_signature', 'key_encipherment'],
 *   ext_key_usage: ['server_auth'],
 * });
 * const srvPem = srvCert.pem();
 */
export function generate_cert(opts) {};

/**
 * Assemble a PKCS#12 bundle.
 *
 * Packages a leaf certificate, its private key, and optional CA chain into
 * an encrypted PKCS#12 `.p12` file. All bags are encrypted with the same
 * password; the bundle is authenticated with an HMAC-SHA1 MAC.
 *
 * Key/certificate linkage is established via a `localKeyId` attribute
 * (SHA-1 hash of the leaf DER certificate).
 *
 * Returns the raw DER binary of the PKCS#12 file on success.
 *
 * Returns `null` on failure.
 *
 * @function module:pkgen#generate_pkcs12
 *
 * @param {Object} opts
 * Bundle options:
 * - `password` {string} **(required)** — bundle password. Converted to
 *   UTF-16BE for PKCS#12 key derivation.
 * - `cert` {string} **(required)** — PEM-encoded leaf certificate.
 * - `key` {PkgenKey} **(required)** — private key matching `cert`.
 * - `extra` {string[]} (optional) — additional PEM certificates to include
 *   as CA/intermediate certs. Each must be a complete PEM string with
 *   `-----BEGIN CERTIFICATE-----` markers.
 * - `legacy` {boolean} (default `false`) — encryption scheme:
 *   - `false` (default): modern PBES2 with PBKDF2-HMAC-SHA256 +
 *     AES-256-CBC (2048 iterations). Supported by OpenSSL 3+,
 *     modern browsers and OS keychains.
 *   - `true`: legacy PBE-SHA1-3DES (PKCS#12 v1 KDF, 2048 iterations).
 *     Use for compatibility with older Windows, macOS Keychain, and
 *     Java < 9 importers.
 *
 * @returns {?string}
 * Raw DER bytes of the PKCS#12 file (binary string).
 *
 * @example
 * import * as fs from 'fs';
 *
 * const p12 = pk.generate_pkcs12({
 *   password: 'hunter2',
 *   cert:     leafPem,
 *   key:      leafKey,
 *   extra:    [caPem],
 * });
 *
 * if (!p12)
 *   die(`PKCS#12 failed: ${pk.error()}\n`);
 *
 * const f = fs.open('/tmp/client.p12', 'w');
 * f.write(p12);
 * f.close();
 *
 * // Legacy mode for Windows XP / Java 8 compatibility
 * const legacyP12 = pk.generate_pkcs12({
 *   password: 'hunter2',
 *   cert:     leafPem,
 *   key:      leafKey,
 *   legacy:   true,
 * });
 */
export function generate_pkcs12(opts) {};

/**
 * Serialise the key to PEM format.
 *
 * Returns the PEM-encoded private key (default) or public key.
 *
 * Returns `null` on mbedtls serialisation error.
 *
 * @function module:pkgen.pk#pem
 *
 * @param {boolean} [pub=false]
 * When truthy, export only the public key.
 *
 * @returns {?string}
 *
 * @example
 * const key = pk.generate_key({ type: 'rsa', size: 2048 });
 * const privatePem = key.pem();        // private key
 * const publicPem  = key.pem(true);    // public key only
 */

/**
 * Serialise the key to DER format.
 *
 * Returns the DER-encoded private key (default) or public key as a raw
 * binary string. mbedtls writes DER from the end of a 32 KiB buffer, so
 * the output is a slice at the end of that buffer — values over 32 KiB
 * will fail.
 *
 * Returns `null` on serialisation error.
 *
 * @function module:pkgen.pk#der
 *
 * @param {boolean} [pub=false]
 * When truthy, export only the public key DER.
 *
 * @returns {?string}
 *
 * @example
 * const key = pk.generate_key({ type: 'ec', curve: 'secp256r1' });
 * const privDer = key.der();
 */

/**
 * Sign and serialise the certificate to PEM format.
 *
 * This is where the actual signing operation (`mbedtls_x509write_crt_pem`)
 * takes place. Can be called multiple times to re-sign with the same
 * parameters (e.g. to produce both PEM and DER).
 *
 * Returns the PEM-encoded signed certificate string.
 *
 * Returns `null` on signing or serialisation failure.
 *
 * @function module:pkgen.crt#pem
 *
 * @returns {?string}
 *
 * @example
 * const cert = pk.generate_cert({ /* … *\/ });
 * const pem  = cert.pem();
 * if (!pem)
 *   die(`Signing failed: ${pk.error()}\n`);
 */

/**
 * Sign and serialise the certificate to DER format.
 *
 * Like {@link module:pkgen.crt#pem|pem()}, the signing operation happens
 * here. Returns the raw DER binary string.
 *
 * Returns `null` on failure.
 *
 * @function module:pkgen.crt#der
 *
 * @returns {?string}
 *
 * @example
 * const der = cert.der();
 * // write raw DER bytes
 */
