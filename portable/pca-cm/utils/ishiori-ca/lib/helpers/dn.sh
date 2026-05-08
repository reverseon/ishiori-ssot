# dn.sh — DN (Distinguished Name) formatting helpers

print_dn_table() {
    local label="$1" dn="$2"
    echo "$label"
    echo "$dn" | tr ',' '\n' | sed 's/^ *//' | awk -F'=' '
        /^CN=/           { printf "  %-30s %s\n", "Common Name (CN):",      substr($0, index($0,"=")+1) }
        /^emailAddress=/ { printf "  %-30s %s\n", "Email (emailAddress):",  substr($0, index($0,"=")+1) }
        /^O=/            { printf "  %-30s %s\n", "Organization (O):",      substr($0, index($0,"=")+1) }
        /^OU=/           { printf "  %-30s %s\n", "Org Unit (OU):",         substr($0, index($0,"=")+1) }
        /^C=/            { printf "  %-30s %s\n", "Country (C):",           substr($0, index($0,"=")+1) }
        /^ST=/           { printf "  %-30s %s\n", "State/Province (ST):",   substr($0, index($0,"=")+1) }
        /^L=/            { printf "  %-30s %s\n", "Locality (L):",          substr($0, index($0,"=")+1) }
    '
}
