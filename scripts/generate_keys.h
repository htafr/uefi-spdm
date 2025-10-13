#include <gnutls/abstract.h>
#include <gnutls/crypto.h>
#include <gnutls/gnutls.h>
#include <gnutls/x509.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SHA256_SIZE 0x20
#define CODE_SIZE 0x37C000
#define RSA_PSS_2048_SIZE 0x100
#define ONE_YEAR 0x1E1853E

#ifdef DEBUG
#define OVMF_CODE "edk2/Build/OvmfX64/DEBUG_GCC5/FV/OVMF_CODE.fd"
#elifdef RELEASE
#define OVMF_CODE "edk2/Build/OvmfX64/RELEASE_GCC5/FV/OVMF_CODE.fd"
#endif

#define PK "keys/PK.key"
#define CA_PEM "keys/PK.crt"
#define CA_DER "keys/PK.der"
#define KEK "keys/KEK.key"
#define KEK_CERT_PEM "keys/KEK.crt"
#define KEK_CERT_DER "keys/KEK.der"
#define DB "keys/DB.key"
#define DB_CERT_PEM "keys/DB.crt"
#define DB_CERT_DER "keys/DB.der"
#define CSR "keys/CSR.key"
#define CSR_CERT_PEM "keys/CSR.crt"
#define CSR_CERT_DER "keys/CSR.der"
#define HCRTM_HASH "keys/HCRTM.hash"
#define SIGNED_HCRTM "keys/HCRTM.sig"

#define PrintBuf(Buf, Len)                                                     \
  for (size_t Idx = 0; Idx < Len; Idx++) {                                     \
    if (Idx == 0)                                                              \
      printf("\t");                                                            \
    else if (Idx % 32 == 0)                                                    \
      printf("\n\t");                                                          \
    printf("%02X ", Buf[Idx]);                                                 \
  }                                                                            \
  printf("\n");

#define ASSERT_EQUAL(Compare, Value, Return, Fmt, ...)                         \
  if (Compare != Value) {                                                      \
    printf(Fmt, ##__VA_ARGS__);                                                \
    Return = EXIT_FAILURE;                                                     \
    goto exit;                                                                 \
  }

#define ASSERT_NEQUAL(Compare, Value, Return, Fmt, ...)                        \
  if (Compare == Value) {                                                      \
    printf(Fmt, ##__VA_ARGS__);                                                \
    Return = EXIT_FAILURE;                                                     \
    goto exit;                                                                 \
  }
