# parse.sh — CA database parsing helpers

# Parse index.txt into structured output
# Fields (tab-separated): status, expiry, revocation_info, serial, filename, subject
# Note: revocation_info is empty for valid certs (consecutive tabs); use awk to preserve empty fields
parse_index() {
    local filter="$1" search="$2" sort_by="${3:-serial}"

    local sort_key
    case "$sort_by" in
        expiry)       sort_key="-k2,2" ;;
        revoked-date) sort_key="-k3,3" ;;
        *)            sort_key="-k4,4" ;;
    esac

    sort -t$'\t' $sort_key -r "$INDEX_FILE" | awk -v filter="$filter" -v search="$search" 'BEGIN { FS="\t" }

    function fmt_date(d,    y,m,day,h,min) {
        if (d == "") return ""
        y   = "20" substr(d,1,2)
        m   = substr(d,3,2)
        day = substr(d,5,2)
        h   = substr(d,7,2)
        min = substr(d,9,2)
        return y "-" m "-" day " " h ":" min
    }

    {
        status=$1; expiry=$2; revinfo=$3; serial=$4; subject=$6

        if (filter == "valid"   && status != "V") next
        if (filter == "revoked" && status != "R") next

        cn = subject; sub(/.*CN=/, "", cn); sub(/\/.*/, "", cn)
        if (search != "" && index(tolower(cn), tolower(search)) == 0) next

        if      (status == "V") status_label = "Valid"
        else if (status == "R") status_label = "Revoked"
        else if (status == "E") status_label = "Expired"
        else                    status_label = status

        rev_date=""; rev_reason=""
        if (status == "R" && revinfo != "") {
            n = split(revinfo, parts, ",")
            rev_date = fmt_date(parts[1])
            rev_reason = (n > 1) ? parts[2] : "unspecified"
        }

        printf "%-9s %-8s %-17s %-17s %-24s %s\n", status_label, serial, fmt_date(expiry), rev_date, rev_reason, cn
    }'
}
