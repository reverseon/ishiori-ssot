# x509.sh — openssl x509 field extraction helpers

x509_subject()    { openssl x509 -in "$1" -noout -subject  -nameopt RFC2253 2>/dev/null | sed 's/^subject=//'; }
x509_issuer()     { openssl x509 -in "$1" -noout -issuer   -nameopt RFC2253 2>/dev/null | sed 's/^issuer=//'; }
x509_serial()     { openssl x509 -in "$1" -noout -serial                    2>/dev/null | sed 's/^serial=//'; }
x509_not_before() { openssl x509 -in "$1" -noout -startdate                 2>/dev/null | sed 's/^notBefore=//'; }
x509_not_after()  { openssl x509 -in "$1" -noout -enddate                   2>/dev/null | sed 's/^notAfter=//'; }
x509_san()        { openssl x509 -in "$1" -noout -ext subjectAltName        2>/dev/null | grep -v "^X509v3" | tr -d ' '; true; }
