#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <gnutls/gnutls.h>
#include <gnutls/crypto.h>
#include <gnutls/x509.h>
#include <gnutls/abstract.h>

#define SHA256_SIZE       0x20
#define CODE_SIZE         0x37C000
#define RSA_PSS_2048_SIZE 0x100

#define OVMF_CODE     "edk2/Build/OvmfX64/DEBUG_GCC5/FV/OVMF_CODE.fd"
#define PK            "keys/PK.key"
#define HCRTM_HASH    "keys/HCRTM.hash"
#define SIGNED_HCRTM  "keys/HCRTM.sig"

#define PrintBuf(Buf, Len)                          \
          for (size_t Idx = 0; Idx < Len; Idx++) {  \
            if (Idx == 0) printf("\t");             \
            else if (Idx % 32 == 0) printf("\n\t"); \
            printf("%02X ", Buf[Idx]);              \
          }                                         \
          printf("\n");

#define ASSERT_EQUAL(Compare, Value, Return, Fmt, ...)  \
          if (Compare != Value) {                       \
            printf(Fmt, __VA_ARGS__);                   \
            Return = EXIT_FAILURE;                      \
            goto exit;                                  \
          }

#define ASSERT_NEQUAL(Compare, Value, Return, Fmt, ...)   \
          if (Compare == Value) {                         \
            printf(Fmt, __VA_ARGS__);                     \
            Return = EXIT_FAILURE;                        \
            goto exit;                                    \
          }

int main(int argc, char *argv[])
{
  gnutls_privkey_t PrivKey = calloc(1, sizeof(gnutls_privkey_t));
  gnutls_pubkey_t PubKey = calloc(1, sizeof(gnutls_pubkey_t));
  gnutls_x509_privkey_t X509PrivKey = calloc(1, sizeof(gnutls_x509_privkey_t));
  gnutls_x509_spki_t Spki = calloc(1, sizeof(gnutls_x509_spki_t));
  gnutls_datum_t *Datum = calloc(1, sizeof(gnutls_datum_t));
  gnutls_datum_t *HcrtmDatum = calloc(1, sizeof(gnutls_datum_t));
  gnutls_datum_t HcrtmSignature = { NULL, 0 };
  uint8_t OvmfCode[CODE_SIZE] = { 0 };
  uint8_t OvmfCodeHash[SHA256_SIZE] = { 0 };
  uint8_t Hcrtm[SHA256_SIZE] = { 0 };
  uint8_t Tmp[2 * SHA256_SIZE] = { 0 };
  FILE *PrivKeyFp = NULL;
  FILE *OvmfCodeFp = NULL;
  FILE *HcrtmHashFp = NULL;
  FILE *HcrtmSigFp = NULL;
  int Return = EXIT_SUCCESS;

  // Initialize GnuTLS
  Return = gnutls_global_init();
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "gnutls_global_init - %s\n", gnutls_strerror(Return));

  Return = gnutls_x509_spki_init(&Spki);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "gnutls_x509_spkki_init - %s\n", gnutls_strerror(Return));

  // Generate RSA-PSS 2048 key
  gnutls_x509_spki_set_rsa_pss_params(Spki, GNUTLS_DIG_SHA256, SHA256_SIZE);
  Return = gnutls_privkey_generate(PrivKey, GNUTLS_PK_RSA_PSS, 2048, 0);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "gnutls_privkey_generate - %s\n", gnutls_strerror(Return));

  Return = gnutls_privkey_set_spki(PrivKey, Spki, 0);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "gnutls_privkey_set_spki - %s\n", gnutls_strerror(Return));

  Return = gnutls_privkey_export_x509(PrivKey, &X509PrivKey);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "gnutls_privkey_export_x509 - %s\n", gnutls_strerror(Return));

  Return = gnutls_x509_privkey_export2_pkcs8(X509PrivKey, GNUTLS_X509_FMT_PEM, 
                                          NULL, 0, Datum);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "gnutls_x509_privkey_export2_pkcs8 - %s\n", gnutls_strerror(Return));

  // Persist private key
  PrivKeyFp = fopen(PK, "w+");
  ASSERT_NEQUAL(PrivKeyFp, NULL, Return, "Error opening %s\n", PK);
  Return = fwrite(Datum->data, sizeof(uint8_t), Datum->size, PrivKeyFp);
  ASSERT_EQUAL(Return, Datum->size, Return,
               "Error writing to %s\n", PK);
  Return = fclose(PrivKeyFp);
  ASSERT_EQUAL(Return, 0, Return,
               "Error closing %s\n", PK);

  // Convert to abstract private key
  Return = gnutls_privkey_init(&PrivKey);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "gnutls_privkey_init - %s\n", gnutls_strerror(Return));

  Return = gnutls_privkey_import_x509_raw(PrivKey, Datum, GNUTLS_X509_FMT_PEM,
                                       NULL, 0);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "gnutls_privkey_import_x509_raw - %s\n", gnutls_strerror(Return));

  // Read OVMF code
  OvmfCodeFp = fopen(OVMF_CODE, "rb");
  ASSERT_NEQUAL(OvmfCodeFp, NULL, Return,
                "Error opening %s\n", OVMF_CODE);
  Return = fread(OvmfCode, sizeof(uint8_t), CODE_SIZE, OvmfCodeFp);
  ASSERT_EQUAL(Return, CODE_SIZE, Return,
               "Error reading %s\n", OVMF_CODE);
  Return = fclose(OvmfCodeFp);
  ASSERT_EQUAL(Return, 0, Return,
               "Error closing %s\n", OVMF_CODE);

  // Compute H-CRTM (SHA256)
  Return = gnutls_hash_fast(GNUTLS_DIG_SHA256, OvmfCode, CODE_SIZE, OvmfCodeHash);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "Error computing %s hash - %s\n", OVMF_CODE,  gnutls_strerror(Return));

  Tmp[SHA256_SIZE - 1] = 0x4;
  memcpy(Tmp + SHA256_SIZE, OvmfCodeHash, SHA256_SIZE);

  Return = gnutls_hash_fast(GNUTLS_DIG_SHA256, Tmp, 2 * SHA256_SIZE, Hcrtm);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "Error computing H-CRTM - %s\n", gnutls_strerror(Return));

  // Sign H-CRTM
  HcrtmDatum->size = SHA256_SIZE;
  HcrtmDatum->data = calloc(SHA256_SIZE, sizeof(uint8_t));
  memcpy(HcrtmDatum->data, Hcrtm, SHA256_SIZE);

  Return = gnutls_privkey_sign_data2(PrivKey, GNUTLS_SIGN_RSA_PSS_SHA256, 0,
                                     HcrtmDatum, &HcrtmSignature);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, 
               "Error signing H-CRTM - %s\n", gnutls_strerror(Return));

  // Persist H-CRTM hash and signature
  HcrtmHashFp = fopen(HCRTM_HASH, "w+");
  ASSERT_NEQUAL(HcrtmHashFp, NULL, Return, "Error opening %s\n", HCRTM_HASH);
  Return = fwrite(Hcrtm, sizeof(uint8_t), SHA256_SIZE, HcrtmHashFp);
  ASSERT_EQUAL(Return, SHA256_SIZE, Return,
               "Error writing to %s\n", HCRTM_HASH);
  Return = fclose(HcrtmHashFp);
  ASSERT_EQUAL(Return, 0, Return, "Error closing %s\n", HCRTM_HASH);

  HcrtmSigFp = fopen(SIGNED_HCRTM, "w+");
  ASSERT_NEQUAL(HcrtmSigFp, NULL, Return,
                "Error opening %s\n", SIGNED_HCRTM);
  Return = fwrite(HcrtmSignature.data, sizeof(uint8_t), RSA_PSS_2048_SIZE, HcrtmSigFp);
  ASSERT_EQUAL(Return, RSA_PSS_2048_SIZE, Return,
               "Error writing to %s\n", HCRTM_HASH);
  Return = fclose(HcrtmSigFp);
  ASSERT_EQUAL(Return, 0, Return,
               "Error closing %s\n", SIGNED_HCRTM);

  // Verify signature
  Return = gnutls_pubkey_init(&PubKey);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "Error initializing gnutls_pubkey_t - %s\n", gnutls_strerror(Return));

  Return = gnutls_pubkey_import_privkey(PubKey, PrivKey, 0, 0);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "Error importing public key - %s\n", gnutls_strerror(Return));

  Return = gnutls_pubkey_verify_data2(PubKey, GNUTLS_SIGN_RSA_PSS_SHA256, 0, HcrtmDatum, &HcrtmSignature);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "Error verifying signature - %s\n", gnutls_strerror(Return));

  Return = EXIT_SUCCESS;
exit:
  gnutls_privkey_deinit(PrivKey);
  gnutls_pubkey_deinit(PubKey);
  gnutls_x509_privkey_deinit(X509PrivKey);
  gnutls_x509_spki_deinit(Spki);
  gnutls_free(Datum);
  gnutls_free(HcrtmDatum);
  gnutls_global_deinit();

  return Return;
}
