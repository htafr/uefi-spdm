#include "generate_keys.h"
#include <gnutls/x509.h>

static int GetRandom(void *Buffer, size_t Size)
{
  FILE *Fp = NULL;
  int Return = -1;

  Fp = fopen("/dev/random", "rb");
  if (Fp == NULL) {
    printf("Error opening /dev/random\n");
  }
  Return = fread(Buffer, sizeof(uint8_t), Size, Fp);
  if (Return != Size) {
    printf("Error reading /dev/random\n");
  }
  Return = fclose(Fp);
  if (Return != 0) {
    printf("Error closing /dev/random\n");
  }

  return Return;
}

static int WriteFile(
  uint8_t    *Data,
  size_t     DataSize,
  const char *FileName
)
{
  FILE  *Fp    = NULL;
  int   Return = EXIT_SUCCESS;

  Fp = fopen(FileName, "w+");
  ASSERT_NEQUAL(Fp, NULL, Return, "Error opening %s\n", FileName);
  Return = fwrite(Data, sizeof(uint8_t), DataSize, Fp);
  ASSERT_EQUAL(Return, DataSize, Return,
               "Error writing to %s\n", FileName);
  Return = fclose(Fp);
  ASSERT_EQUAL(Return, 0, Return,
               "Error closing %s\n", FileName);

exit:
  return Return;
}

static int ReadFile(
  uint8_t    *Data,
  size_t     *DataSize,
  const char *FileName
)
{
  size_t  Index   = 0;
  FILE    *Fp     = NULL;
  int     Return  = EXIT_SUCCESS;

  Fp = fopen(OVMF_CODE, "rb");
  ASSERT_NEQUAL(Fp, NULL, Return,
                "Error opening %s\n", FileName);
  Return = fread(Data, sizeof(uint8_t), *DataSize, Fp);
  ASSERT_EQUAL(Return, *DataSize, Return, "Error reading %s\n", FileName);
  Return = fclose(Fp);
  ASSERT_EQUAL(Return, 0, Return,
               "Error closing %s\n", FileName);

  *DataSize = Index;

exit:
  return Return;
}

static int GenerateCertRequestRsa2048(
  gnutls_datum_t  *CAKeyDatum,
  gnutls_datum_t  *CACertDatum,
  gnutls_datum_t  *PrivKeyDatum,
  gnutls_datum_t  *CertRequestDatum,
  gnutls_datum_t  *CertPemDatum,
  gnutls_datum_t  *CertDerDatum,
  const char      *PrivKeyFileName,
  const char      *CertReqFileName,
  const char      *CertFileNamePem,
  const char      *CertFileNameDer
)
{
  gnutls_privkey_t      PrivKey           = calloc(1, sizeof(gnutls_privkey_t));
  gnutls_privkey_t      CAPrivKey         = calloc(1, sizeof(gnutls_privkey_t));
  gnutls_x509_crq_t     CertRequest       = calloc(1, sizeof(gnutls_x509_crq_t));
  gnutls_x509_privkey_t X509PrivKey       = calloc(1, sizeof(gnutls_x509_privkey_t));
  gnutls_x509_privkey_t X509CAPrivKey     = calloc(1, sizeof(gnutls_x509_privkey_t));
  gnutls_x509_crt_t     Cert              = calloc(1, sizeof(gnutls_x509_crt_t));
  gnutls_x509_crt_t     CACert            = calloc(1, sizeof(gnutls_x509_crt_t));
  uint8_t               SerialNumber[20]  = { 0 };
  size_t                SerialNumberSize  = sizeof(SerialNumber);
  int                   Return            = EXIT_SUCCESS;

  // Initialize GnuTLS data
  Return = gnutls_privkey_init(&PrivKey);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_privkey_init - %s\n", gnutls_strerror(Return));
  Return = gnutls_privkey_init(&CAPrivKey);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_privkey_init - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_privkey_init(&X509PrivKey);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_x509_privkey_init - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_privkey_init(&X509CAPrivKey);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_x509_privkey_init - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crq_init(&CertRequest);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_x509_crq_init - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crt_init(&Cert);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "Error initializing X509 CACert - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crt_init(&CACert);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "Error initializing X509 CACert - %s\n", gnutls_strerror(Return));

  // Generate RSA 2048 key
  Return = gnutls_privkey_generate(PrivKey, GNUTLS_PK_RSA, 2048, 0);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_privkey_generate - %s\n", gnutls_strerror(Return));
  Return = gnutls_privkey_export_x509(PrivKey, &X509PrivKey);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_privkey_export_x509 - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_privkey_export2_pkcs8(X509PrivKey, GNUTLS_X509_FMT_PEM, NULL, 0, PrivKeyDatum);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_x509_privkey_export2_pkcs8 - %s\n", gnutls_strerror(Return));

  // Persist private key
  ASSERT_EQUAL(WriteFile(PrivKeyDatum->data, PrivKeyDatum->size, PrivKeyFileName), 
               EXIT_SUCCESS, Return, "Error writing to %s\n", PrivKeyFileName);

  // Import CA private key
  Return = gnutls_x509_privkey_import(X509CAPrivKey, CAKeyDatum, GNUTLS_X509_FMT_PEM);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_x509_privkey_import - %s\n", gnutls_strerror(Return));
  Return = gnutls_privkey_import_x509_raw(CAPrivKey, CAKeyDatum, GNUTLS_X509_FMT_PEM, NULL, 0);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_privkey_import_x509_raw - %s\n", gnutls_strerror(Return));

  // Generate certificate request
  Return = gnutls_x509_crq_set_version(CertRequest, 1);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_x509_crq_set_version - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crq_set_key(CertRequest, X509PrivKey);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_x509_crq_set_key - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crq_sign2(CertRequest, X509PrivKey, GNUTLS_DIG_SHA256, 0);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_x509_crq_sign2 - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crq_export2(CertRequest, GNUTLS_X509_FMT_PEM, CertRequestDatum);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_x509_crq_export2 - %s\n", gnutls_strerror(Return));

  // Persist certificate request
  ASSERT_EQUAL(WriteFile(CertRequestDatum->data, CertRequestDatum->size, CertReqFileName),
               EXIT_SUCCESS, Return, "Error writing to %s\n", CertReqFileName);

  // Import CA certificate
  Return = gnutls_x509_crt_import(CACert, CACertDatum, GNUTLS_X509_FMT_PEM);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_x509_crt_import - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crt_get_authority_key_id(CACert, SerialNumber, &SerialNumberSize, NULL);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_x509_crt_get_authority_key_id - %s\n", gnutls_strerror(Return));

  // Generate certificate
  Return = gnutls_x509_crt_set_crq(Cert, CertRequest);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_x509_crt_set_crq - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crt_set_crq_extensions(Cert, CertRequest);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_x509_crt_set_crq_extensions - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crt_set_version(Cert, 3);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "Error setting certificate version - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crt_set_authority_key_id(Cert, SerialNumber, SerialNumberSize);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "Error setting certificate authority key ID - %s\n", gnutls_strerror(Return));
  ASSERT_EQUAL(GetRandom(SerialNumber, sizeof(SerialNumber)), EXIT_SUCCESS, Return, "Error in GetRandom\n");
  Return = gnutls_x509_crt_set_subject_key_id(Cert, SerialNumber, sizeof(SerialNumber));
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "Error setting certificate subject key ID - %s\n", gnutls_strerror(Return));
  ASSERT_EQUAL(GetRandom(SerialNumber, sizeof(SerialNumber)), EXIT_SUCCESS, Return, "Error in GetRandom\n");
  Return = gnutls_x509_crt_set_serial(Cert, SerialNumber, sizeof(SerialNumber));
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "Error setting certificate serial - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crt_set_expiration_time(Cert, time(NULL) + ONE_YEAR);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "Error setting certificate expiration time - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crt_set_activation_time(Cert, time(NULL));
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "Error setting certificate activation time - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crt_set_key(Cert, X509PrivKey);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "Error setting certificate private key - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crt_set_dn(Cert, "C=BR, ST=SP", NULL);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "Error setting certificate DN - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crt_privkey_sign(Cert, CACert, CAPrivKey, GNUTLS_DIG_SHA256, 0);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "gnutls_x509_crt_privkey_sign - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crt_export2(Cert, GNUTLS_X509_FMT_PEM, CertPemDatum);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "Error exporting PEM certificate - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crt_export2(Cert, GNUTLS_X509_FMT_DER, CertDerDatum);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, "Error exporting DER certificate - %s\n", gnutls_strerror(Return));

  // Persist end certificate
  ASSERT_EQUAL(WriteFile(CertPemDatum->data, CertPemDatum->size, CertFileNamePem),
               EXIT_SUCCESS, Return, "Error writing to %s\n", CertFileNamePem);
  ASSERT_EQUAL(WriteFile(CertDerDatum->data, CertDerDatum->size, CertFileNameDer),
               EXIT_SUCCESS, Return, "Error writing to %s\n", CertFileNameDer);


exit:
  gnutls_privkey_deinit(PrivKey);
  gnutls_privkey_deinit(CAPrivKey);
  gnutls_x509_privkey_deinit(X509PrivKey);
  gnutls_x509_privkey_deinit(X509CAPrivKey);
  gnutls_x509_crq_deinit(CertRequest);
  gnutls_x509_crt_deinit(Cert);
  gnutls_x509_crt_deinit(CACert);
  return Return;
}

/**
 * Generates an RSA 2048 private key and certificate. It also persists 
 * the private key and the certificate.
 *
 * @param       PrivKeyDatum          Private key gnuTLS datum pointer
 * @param       CertDatum             Certificate gnuTLS datum
 * @param       PrivKeyFileName       File name to persist private key
 *
 * @return      EXIT_SUCCESS if no error, EXIT_FAILURE
 *              in case of error
 */
static int GenerateCertRsa2048(
  gnutls_datum_t  *PrivKeyDatum,
  gnutls_datum_t  *CertPemDatum,
  gnutls_datum_t  *CertDerDatum,
  gnutls_datum_t  *CAPrivKeyDatum,
  gnutls_datum_t  *CACertDatum,
  const char      *PrivKeyFileName,
  const char      *CertFileNamePem,
  const char      *CertFileNameDer,
  bool            SignCert
)
{
  gnutls_privkey_t      PrivKey           = calloc(1, sizeof(gnutls_privkey_t));
  gnutls_privkey_t      CAPrivKey         = calloc(1, sizeof(gnutls_privkey_t));
  gnutls_x509_privkey_t X509PrivKey       = calloc(1, sizeof(gnutls_x509_privkey_t));
  gnutls_x509_privkey_t X509CAPrivKey     = calloc(1, sizeof(gnutls_x509_privkey_t));
  gnutls_x509_crt_t     Cert              = calloc(1, sizeof(gnutls_x509_crt_t));
  gnutls_x509_crt_t     CACert            = calloc(1, sizeof(gnutls_x509_crt_t));
  uint8_t               SerialNumber[20]  = { 0 };
  int                   Return            = EXIT_SUCCESS;

  // Initialize gnuTLS data
  Return = gnutls_privkey_init(&PrivKey);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "gnutls_privkey_init - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crt_init(&Cert);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, 
               "Error initializing gnutls_x509_crt_t - %s\n", gnutls_strerror(Return));
  Return = gnutls_privkey_init(&CAPrivKey);
  ASSERT_EQUAL(Return,
               GNUTLS_E_SUCCESS, Return, "gnutls_privkey_init - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_privkey_init(&X509CAPrivKey);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "Error initializing gnutls_x509_privkey_t - %s\n", gnutls_strerror(Return));
  Return = gnutls_x509_crt_init(&CACert);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "Error initializing X509 CACert - %s\n", gnutls_strerror(Return));

  // Generate RSA 2048 key
  Return = gnutls_privkey_generate(PrivKey, GNUTLS_PK_RSA, 2048, 0);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "gnutls_privkey_generate - %s\n", gnutls_strerror(Return));

  Return = gnutls_privkey_export_x509(PrivKey, &X509PrivKey);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "gnutls_privkey_export_x509 - %s\n", gnutls_strerror(Return));

  Return = gnutls_x509_privkey_export2_pkcs8(X509PrivKey, GNUTLS_X509_FMT_PEM, 
                                             NULL, 0, PrivKeyDatum);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, 
               "gnutls_x509_privkey_export2_pkcs8 - %s\n", gnutls_strerror(Return));

  // Persist private key
  ASSERT_EQUAL(WriteFile(PrivKeyDatum->data, PrivKeyDatum->size, PrivKeyFileName), 
               EXIT_SUCCESS, Return, "Error writing to %s\n", PrivKeyFileName);

  // Convert to abstract private key
  Return = gnutls_privkey_import_x509_raw(PrivKey, PrivKeyDatum,
                                          GNUTLS_X509_FMT_PEM, NULL, 0);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "gnutls_privkey_import_x509_raw - %s\n", gnutls_strerror(Return));

  // Generate certificate
  Return = gnutls_x509_crt_set_version(Cert, 3);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, 
               "Error setting certificate version - %s\n", gnutls_strerror(Return));

  ASSERT_EQUAL(GetRandom(SerialNumber, sizeof(SerialNumber)), EXIT_SUCCESS, Return, "Error in GetRandom\n");
  Return = gnutls_x509_crt_set_serial(Cert, SerialNumber, sizeof(SerialNumber));
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "Error setting certificate serial - %s\n", gnutls_strerror(Return));

  Return = gnutls_x509_crt_set_expiration_time(Cert, time(NULL) + ONE_YEAR);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "Error setting certificate expiration time - %s\n", gnutls_strerror(Return));

  Return = gnutls_x509_crt_set_activation_time(Cert, time(NULL));
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, 
               "Error setting certificate activation time - %s\n", gnutls_strerror(Return));

  Return = gnutls_x509_crt_set_key(Cert, X509PrivKey);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, 
               "Error setting certificate private key - %s\n", gnutls_strerror(Return));

  ASSERT_EQUAL(GetRandom(SerialNumber, sizeof(SerialNumber)), EXIT_SUCCESS, Return, "Error in GetRandom\n");
  Return = gnutls_x509_crt_set_subject_key_id(Cert, SerialNumber, sizeof(SerialNumber));
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, 
               "Error setting certificate subject key ID - %s\n", gnutls_strerror(Return));

  Return = gnutls_x509_crt_set_authority_key_id(Cert, SerialNumber, sizeof(SerialNumber));
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, 
               "Error setting certificate authority key ID - %s\n", gnutls_strerror(Return));

  Return = gnutls_x509_crt_set_basic_constraints(Cert, 1, 1);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, 
                "Error setting certificate basic constraints - %s\n", gnutls_strerror(Return));

  Return = gnutls_x509_crt_set_dn(Cert, "CN = LARC", NULL);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, 
              "Error setting certificate DN - %s\n", gnutls_strerror(Return));

  Return = gnutls_x509_crt_sign2(Cert, Cert, X509PrivKey, GNUTLS_DIG_SHA256, 0);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
              "Error signing certificate - %s\n", gnutls_strerror(Return));

  if (SignCert && (CAPrivKeyDatum != NULL) && (CACertDatum != NULL)) {
    // Import CA private key
    Return = gnutls_x509_privkey_import2(X509CAPrivKey, CAPrivKeyDatum, GNUTLS_X509_FMT_PEM,
                                         NULL, 0);
    ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
                 "gnutls_x509_privkey_import2 - %s\n", gnutls_strerror(Return));

    Return = gnutls_x509_crt_import(CACert, CACertDatum, GNUTLS_X509_FMT_PEM);
    ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
                 "Error importing X509 CACert - %s\n", gnutls_strerror(Return));

    Return = gnutls_x509_crt_sign2(Cert, CACert, X509CAPrivKey, GNUTLS_DIG_SHA256, 0);
    ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, 
                 "Error signing certificate - %s\n", gnutls_strerror(Return));
  }

  Return = gnutls_x509_crt_export2(Cert, GNUTLS_X509_FMT_PEM, CertPemDatum);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, 
               "Error exporting PEM certificate - %s\n", gnutls_strerror(Return));

  ASSERT_EQUAL(WriteFile(CertPemDatum->data, CertPemDatum->size, CertFileNamePem),
               EXIT_SUCCESS, Return, "Error writing to %s\n", CertFileNamePem);

  Return = gnutls_x509_crt_export2(Cert, GNUTLS_X509_FMT_DER, CertDerDatum);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "Error exporting DER certificate - %s\n", gnutls_strerror(Return));

  ASSERT_EQUAL(WriteFile(CertDerDatum->data, CertDerDatum->size, CertFileNameDer),
               EXIT_SUCCESS, Return, "Error writing to %s\n", CertFileNameDer);

exit:
  gnutls_privkey_deinit(PrivKey);
  gnutls_privkey_deinit(CAPrivKey);
  gnutls_x509_privkey_deinit(X509PrivKey);
  gnutls_x509_privkey_deinit(X509CAPrivKey);
  gnutls_x509_crt_deinit(Cert);
  gnutls_x509_crt_deinit(CACert);

  return Return;
}

static int ComputeSignedHcrtm(
  gnutls_privkey_t  PrivKey
)
{
  gnutls_datum_t  HcrtmSignature  = { NULL, 0 };
  gnutls_datum_t  *HcrtmDatum     = calloc(1, sizeof(gnutls_datum_t));
  gnutls_pubkey_t PubKey          = calloc(1, sizeof(gnutls_pubkey_t));
  uint8_t         *Firmware       = calloc(1, CODE_SIZE);
  uint8_t         *FirmwareHash   = calloc(1, SHA256_SIZE);
  uint8_t         *TmpBuffer      = calloc(2, SHA256_SIZE);
  uint8_t         *Hcrtm          = calloc(1, SHA256_SIZE);
  size_t          FirmwareSize    = CODE_SIZE;
  int             Return          = EXIT_SUCCESS;

  Return = ReadFile(Firmware, &FirmwareSize, OVMF_CODE);
  ASSERT_EQUAL(Return, EXIT_SUCCESS, Return, "Error reading %s\n", OVMF_CODE);

  // Compute H-CRTM (SHA256)
  Return = gnutls_hash_fast(GNUTLS_DIG_SHA256, Firmware, CODE_SIZE, FirmwareHash);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "Error computing %s hash - %s\n", OVMF_CODE,  gnutls_strerror(Return));

  TmpBuffer[SHA256_SIZE - 1] = 0x4;
  memcpy(TmpBuffer + SHA256_SIZE, FirmwareHash, SHA256_SIZE);

  Return = gnutls_hash_fast(GNUTLS_DIG_SHA256, TmpBuffer, 2 * SHA256_SIZE, Hcrtm);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "Error computing H-CRTM - %s\n", gnutls_strerror(Return));

  // Sign H-CRTM
  HcrtmDatum->size = SHA256_SIZE;
  HcrtmDatum->data = calloc(SHA256_SIZE, sizeof(uint8_t));
  memcpy(HcrtmDatum->data, Hcrtm, SHA256_SIZE);

  Return = gnutls_privkey_sign_data2(PrivKey, GNUTLS_SIGN_RSA_SHA256, 0,
                                     HcrtmDatum, &HcrtmSignature);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return, 
               "Error signing H-CRTM - %s\n", gnutls_strerror(Return));

  // Persist H-CRTM hash and signature
  Return = WriteFile(Hcrtm, SHA256_SIZE, HCRTM_HASH);
  ASSERT_EQUAL(Return, EXIT_SUCCESS, Return, "Error writing to %s\n", HCRTM_HASH);

  Return = WriteFile(HcrtmSignature.data, HcrtmSignature.size, SIGNED_HCRTM);
  ASSERT_EQUAL(Return, EXIT_SUCCESS, Return, "Error writing to %s\n", SIGNED_HCRTM);

  // Verify signature
  Return = gnutls_pubkey_init(&PubKey);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "Error initializing gnutls_pubkey_t - %s\n", gnutls_strerror(Return));

  Return = gnutls_pubkey_import_privkey(PubKey, PrivKey, 0, 0);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "Error importing public key - %s\n", gnutls_strerror(Return));

  Return = gnutls_pubkey_verify_data2(PubKey, GNUTLS_SIGN_RSA_SHA256, 0, HcrtmDatum, &HcrtmSignature);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "Error verifying signature - %s\n", gnutls_strerror(Return));

exit:
  gnutls_pubkey_deinit(PubKey);
  gnutls_free(HcrtmDatum);
  free(Firmware);
  free(FirmwareHash);
  free(TmpBuffer);
  free(Hcrtm);
  return Return;
}

int main(int argc, char *argv[])
{
  gnutls_privkey_t  PrivKey           = calloc(1, sizeof(gnutls_privkey_t));
  gnutls_datum_t    *PKDatum          = calloc(1, sizeof(gnutls_datum_t));
  gnutls_datum_t    *CAPemDatum       = calloc(1, sizeof(gnutls_datum_t));
  gnutls_datum_t    *CADerDatum       = calloc(1, sizeof(gnutls_datum_t));
  gnutls_datum_t    *KEKDatum         = calloc(1, sizeof(gnutls_datum_t));
  gnutls_datum_t    *KEKCertPemDatum  = calloc(1, sizeof(gnutls_datum_t));
  gnutls_datum_t    *KEKCertDerDatum  = calloc(1, sizeof(gnutls_datum_t));
  gnutls_datum_t    *DBKeyDatum       = calloc(1, sizeof(gnutls_datum_t));
  gnutls_datum_t    *DBCertPemDatum   = calloc(1, sizeof(gnutls_datum_t));
  gnutls_datum_t    *DBCertDerDatum   = calloc(1, sizeof(gnutls_datum_t));
  gnutls_datum_t    *CertReqDatum     = calloc(1, sizeof(gnutls_datum_t));
  int               Return            = EXIT_SUCCESS;

  // Initialize GnuTLS
  Return = gnutls_global_init();
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "gnutls_global_init - %s\n", gnutls_strerror(Return));

  // Generate RSA 2048 Platform Key
  Return = GenerateCertRsa2048(PKDatum, CAPemDatum, CADerDatum,
                               NULL, NULL,
                               PK, CA_PEM, CA_DER, false);
  ASSERT_EQUAL(Return, EXIT_SUCCESS, Return, "Error generating %s\n", PK);

  Return = GenerateCertRsa2048(DBKeyDatum, DBCertPemDatum, DBCertDerDatum, NULL, NULL, 
                               DB, DB_CERT_PEM, DB_CERT_DER, false);
  ASSERT_EQUAL(Return, EXIT_SUCCESS, Return, "Error generating %s\n", DB);

  // Generate RSA 2048 KEK

  // Generate Certificate Request
  Return = GenerateCertRequestRsa2048(PKDatum, CAPemDatum, KEKDatum, CertReqDatum, KEKCertPemDatum,  KEKCertDerDatum,
                                      KEK, CSR_CERT_PEM, KEK_CERT_PEM, KEK_CERT_DER);
  ASSERT_EQUAL(Return, EXIT_SUCCESS, Return, "Error generating %s\n", KEK);

  // Convert to abstract private key
  Return = gnutls_privkey_init(&PrivKey);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "gnutls_privkey_init - %s\n", gnutls_strerror(Return));

  Return = gnutls_privkey_import_x509_raw(PrivKey, PKDatum, GNUTLS_X509_FMT_PEM,
                                       NULL, 0);
  ASSERT_EQUAL(Return, GNUTLS_E_SUCCESS, Return,
               "gnutls_privkey_import_x509_raw - %s\n", gnutls_strerror(Return));

  Return = ComputeSignedHcrtm(PrivKey);
  ASSERT_EQUAL(Return, EXIT_SUCCESS, Return, "Error computing H-CRTM\n");

exit:
  gnutls_privkey_deinit(PrivKey);
  gnutls_free(PKDatum);
  gnutls_free(CAPemDatum);
  gnutls_free(CADerDatum);
  gnutls_free(KEKDatum);
  gnutls_free(KEKCertPemDatum);
  gnutls_free(KEKCertDerDatum);
  gnutls_global_deinit();

  return Return;
}
