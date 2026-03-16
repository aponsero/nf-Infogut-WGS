#!/bin/bash
DIR1="ground_truth"
DIR2="../results/06_metastandard"
files1=($(ls "$DIR1" | sort))
files2=($(ls "$DIR2" | sort))
if [ ${#files1[@]} -ne ${#files2[@]} ]; then
    echo "Directories have different number of files: ${#files1[@]} vs ${#files2[@]}"
    exit 1
fi
echo "Comparing ${#files1[@]} files by content (column-order independent)..."
echo "----------------------------------------"
passed=0
failed=0
compare_tsv() {
    local f1="$1"
    local f2="$2"
    # Get headers from both files
    header1=$(head -1 "$f1")
    header2=$(head -1 "$f2")
    # Check both files have the same column names (regardless of order)
    cols1=$(echo "$header1" | tr '\t' '\n' | sort | tr '\n' '\t')
    cols2=$(echo "$header2" | tr '\t' '\n' | sort | tr '\n' '\t')
    if [ "$cols1" != "$cols2" ]; then
        echo "  Column names differ:"
        echo "  Only in f1: $(comm -23 <(echo "$header1" | tr '\t' '\n' | sort) <(echo "$header2" | tr '\t' '\n' | sort))"
        echo "  Only in f2: $(comm -13 <(echo "$header1" | tr '\t' '\n' | sort) <(echo "$header2" | tr '\t' '\n' | sort))"
        return 1
    fi
    # Round numeric values to 2 decimal places, reorder f2 columns to match f1, then compare
    diff <(awk '
            NR == 1 { print; next }
            {
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^-?[0-9]+(\.[0-9]+)?$/) $i = sprintf("%.2f", $i)
                }
                print
            }
         ' FS='\t' OFS='\t' "$f1") \
         <(awk -v hdr="$header1" '
            BEGIN {
                n = split(hdr, order, "\t")
                for (i = 1; i <= n; i++) target[order[i]] = i
            }
            NR == 1 {
                # Build mapping: position in f2 -> position in f1
                for (j = 1; j <= NF; j++) colmap[j] = target[$j]
                # Print header in f1 order
                for (i = 1; i <= n; i++) {
                    printf "%s%s", order[i], (i < n ? "\t" : "\n")
                }
                next
            }
            {
                split($0, row, "\t")
                for (i = 1; i <= n; i++) {
                    for (j = 1; j <= NF; j++) {
                        if (colmap[j] == i) {
                            val = row[j]
                            if (val ~ /^-?[0-9]+(\.[0-9]+)?$/) val = sprintf("%.2f", val)
                            printf "%s%s", val, (i < n ? "\t" : "\n")
                            break
                        }
                    }
                }
            }
         ' FS='\t' "$f2")
}
for i in "${!files1[@]}"; do
    f1="$DIR1/${files1[$i]}"
    f2="$DIR2/${files2[$i]}"
    result=$(compare_tsv "$f1" "$f2")
    if [ -z "$result" ]; then
        echo "✅ MATCH:    ${files1[$i]}  <->  ${files2[$i]}"
        ((passed++))
    else
        echo "❌ MISMATCH: ${files1[$i]}  <->  ${files2[$i]}"
        echo "$result"
        ((failed++))
    fi
done
echo "----------------------------------------"
echo "Results: $passed passed, $failed failed"
if [ $failed -gt 0 ]; then exit 1; fi
