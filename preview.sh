#!/usr/bin/env bash
# Preview helper for simple cat-printer text (not images or PostScript).
set -euo pipefail

DPI=200
MAX_WIDTH_CM=4.88
MAX_WIDTH_PX=384
DEFAULT_TEXT='Hello World'
DEFAULT_FONT_SIZE=24
CROP_MM=5
DEFAULT_FEED_MM=5
FRAME_STROKE_PX=3
PLACEHOLDER_MAC='AA:BB:CC:DD:EE:FF'
UVX_FROM='git+https://github.com/pavelsr/Cat-Printer'
PRINTER_MODELS=(GB01 GB02 GB03 GT01 YT01 MX05 MX06 MX08 MX09 MX10 MX11 PD01 SC03h MXTP)

magick_bin=""
print_cmd=()
print_cmd_display=""
pad_px=0

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: preview.sh [OPTIONS]

Preview simple text for a cat printer. This script is for plain text only —
not images and not PostScript / Ghostscript files.

Use it to settle on a font family and size before a bulk print run — for
example warehouse location labels, ISO 780 / GOST 14192-96 shipping marks,
and similar text-only labels.

Interactive flow (skipped when the matching flag is set):
  1. Text to preview (default: Hello World)
  2. Font name (default: a system monospace font; 1-3 pick a helper)
  3. Either fit size in cm (max width 4.88; e.g. 4:2.5, 4, :2.5;
     with a crop frame this is the final size, including the 5 mm inset)
     or font size in px (default: 24) if fit is skipped
  4. Whether to show real sizes in centimeters [Y/n]
  5. Whether to add a crop frame: 5 mm from the text, 3 px stroke inward [Y/n];
     after Y, inset in millimeters (integer, default 5)

Writes /tmp/cat-printer/preview_YYYY_MM_DD_HH_MM_SS.pbm and prints that path
plus a real-print command (without dimension lines). A crop frame is included
in the print command when enabled. The print command uses --feed 5 unless
you override it.

Options:
  -h, --help              Show this help and exit
  --text TEXT             Text to preview
  --font NAME             Font family, or 1-3 for a listed mono font
  --fit SIZE              Final box in cm: 4:2.5, 4, or :2.5
                          (includes the 5 mm crop frame when it is enabled)
  --font-size N           Font size in pixels (not with --fit; default 24)
  --feed N                Paper feed after print, in millimeters (default 5)
  --real-sizes            Draw cm dimension lines on the preview
  --no-real-sizes         Do not draw dimension lines
  --crop-frame            Add a crop frame (5 mm inset, 3 px inward stroke)
  --no-crop-frame         Do not add a crop frame

Requires ImageMagick, fontconfig, and cat-printer (or uvx).
Tested with bash 5.3.9.

Examples:
  # Interactive
  ./preview.sh

  # Fit text into 4 x 2.5 cm, Courier, no dimension overlay
  ./preview.sh --text 'Hello World' --font Courier --fit 4:2.5 --no-real-sizes

  # Width only (max printable width is 4.88 cm)
  ./preview.sh --text 'Hello World' --fit 4

  # Height only
  ./preview.sh --text 'Hello World' --fit :2.5

  # Fixed font size instead of a cm box
  ./preview.sh --text 'Hello World' --font-size 24 --font 'PT Mono Bold' --real-sizes

  # Override paper feed in the printed command (default is 5 mm)
  ./preview.sh --text 'Hello World' --fit 4:2.5 --feed 0
EOF
}

require_arg() {
    [ "${2-}" ] || die "$1 requires a value (try --help)"
}

require_imagemagick() {
    if command -v magick >/dev/null 2>&1; then
        magick_bin="$(command -v magick)"
        return
    fi
    if command -v convert >/dev/null 2>&1; then
        magick_bin="$(command -v convert)"
        return
    fi
    cat >&2 <<'EOF'
error: ImageMagick is not installed
Install on Ubuntu/Debian:
  sudo apt install imagemagick
EOF
    exit 1
}

require_cat_printer() {
    if command -v cat-printer >/dev/null 2>&1; then
        print_cmd=(cat-printer)
        print_cmd_display='cat-printer'
        return
    fi
    if ! command -v uvx >/dev/null 2>&1; then
        cat >&2 <<'EOF'
error: cat-printer is not installed, and uvx was not found
Install uv (provides uvx):
  curl -LsSf https://astral.sh/uv/install.sh | sh
EOF
        exit 1
    fi
    print_cmd=(uvx --from "$UVX_FROM" python printer.py)
    print_cmd_display="uvx --from ${UVX_FROM} python printer.py"
}

im_identify() {
    if command -v magick >/dev/null 2>&1; then
        magick identify "$@"
    else
        identify "$@"
    fi
}

im_list_fonts() {
    if [ "$(basename "$magick_bin")" = convert ]; then
        "$magick_bin" -list font
    else
        magick -list font
    fi
}

im_font_exists() {
    local query="$1"
    local hyphen="${query// /-}"
    im_list_fonts 2>/dev/null | awk -v q="$query" -v h="$hyphen" '
        $1 == "Font:" && ($2 == q || $2 == h) { found = 1 }
        END { exit !found }
    '
}

prompt() {
    local dest="$1"
    local message="$2"
    local value=""
    if { printf '' >/dev/tty; } 2>/dev/null; then
        printf '%s' "$message" > /dev/tty
        IFS= read -r value < /dev/tty || true
    else
        printf '%s' "$message"
        IFS= read -r value || true
    fi
    printf -v "$dest" '%s' "$value"
}

has_tty() {
    { printf '' >/dev/tty; } 2>/dev/null
}

prompt_yn() {
    local dest="$1"
    local message="$2"
    local raw=""
    if has_tty; then
        prompt raw "$message"
        case "${raw:-Y}" in
            ''|Y|y|yes|YES)
                printf -v "$dest" '1'
                ;;
            n|N|no|NO)
                printf -v "$dest" '0'
                ;;
            *)
                die "answer must be Y or n, got: $raw"
                ;;
        esac
    else
        printf -v "$dest" '1'
    fi
}

px_to_cm() {
    awk -v px="$1" -v dpi="$DPI" 'BEGIN { printf "%.2f", px * 2.54 / dpi }'
}

cm_to_px() {
    awk -v cm="$1" -v dpi="$DPI" 'BEGIN { printf "%d", cm * dpi / 2.54 + 0.5 }'
}

is_cm_number() {
    [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

cm_gt() {
    awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'
}

shell_quote() {
    local s=$1
    printf "'%s'" "${s//\'/\'\\\'\'}"
}

escape_caption() {
    local s=$1
    s=${s//%/%%}
    printf '%s' "$s"
}

parse_fit() {
    local spec=$1
    fit_w_px=""
    fit_h_px=""
    local width="" height=""
    case "$spec" in
        '')
            return
            ;;
        :*)
            height="${spec#:}"
            ;;
        *:*)
            width="${spec%%:*}"
            height="${spec#*:}"
            ;;
        *)
            width="$spec"
            ;;
    esac
    if [ -n "$width" ]; then
        is_cm_number "$width" || die "fit width must be a number, got: $width"
        cm_gt "$width" "$MAX_WIDTH_CM" && die "fit width ${width} cm exceeds max ${MAX_WIDTH_CM} cm"
        awk -v w="$width" 'BEGIN { exit !(w > 0) }' || die 'fit width must be greater than 0'
        fit_w_px="$(cm_to_px "$width")"
        [ "$fit_w_px" -gt "$MAX_WIDTH_PX" ] && fit_w_px="$MAX_WIDTH_PX"
    fi
    if [ -n "$height" ]; then
        is_cm_number "$height" || die "fit height must be a number, got: $height"
        awk -v h="$height" 'BEGIN { exit !(h > 0) }' || die 'fit height must be greater than 0'
        fit_h_px="$(cm_to_px "$height")"
    fi
    [ -n "$fit_w_px" ] || [ -n "$fit_h_px" ] || die "invalid fit size: $spec"
}

reserve_crop_in_fit() {
    local frame=$((2 * pad_px))
    if [ -n "$fit_w_px" ]; then
        [ "$fit_w_px" -gt "$frame" ] || die 'fit width is smaller than the crop frame inset'
        fit_w_px=$((fit_w_px - frame))
    fi
    if [ -n "$fit_h_px" ]; then
        [ "$fit_h_px" -gt "$frame" ] || die 'fit height is smaller than the crop frame inset'
        fit_h_px=$((fit_h_px - frame))
    fi
}

estimate_fit_pointsize() {
    local font="$1"
    local sample="$2"
    local box_w="$3"
    local box_h="$4"
    local lw lh
    sample="${sample//$'\n'/ }"
    [ -n "$sample" ] || sample='X'
    read -r lw lh < <("$magick_bin" -font "$font" -pointsize 100 \
        label:"$sample" -format '%w %h\n' info: 2>/dev/null || true)
    [ -n "$lw" ] && [ "$lw" -gt 0 ] && [ -n "$lh" ] && [ "$lh" -gt 0 ] || {
        printf '%s\n' "$DEFAULT_FONT_SIZE"
        return
    }
    local est_w="" est_h=""
    if [ -n "$box_w" ]; then
        est_w="$(awk -v bw="$box_w" -v lw="$lw" 'BEGIN { printf "%d", 100 * bw / lw + 0.5 }')"
    fi
    if [ -n "$box_h" ]; then
        est_h="$(awk -v bh="$box_h" -v lh="$lh" 'BEGIN { printf "%d", 100 * bh / lh + 0.5 }')"
    fi
    if [ -n "$est_w" ] && [ -n "$est_h" ]; then
        if [ "$est_w" -lt "$est_h" ]; then
            printf '%s\n' "$est_w"
        else
            printf '%s\n' "$est_h"
        fi
    elif [ -n "$est_w" ]; then
        printf '%s\n' "$est_w"
    else
        printf '%s\n' "$est_h"
    fi
}

annotate_real_sizes() {
    local src="$1"
    local dest="$2"
    local w h
    read -r w h < <(im_identify -format '%w %h\n' "$src")
    [ -n "$w" ] && [ -n "$h" ] || die "could not read image size from $src"

    local cm_w cm_h
    cm_w="$(px_to_cm "$w")"
    cm_h="$(px_to_cm "$h")"

    local left=78
    local top=28
    local right=16
    local bottom=44
    local ox="$left"
    local oy="$top"
    local tick=5
    local new_w=$((w + left + right))
    local new_h=$((h + top + bottom))

    local hx1="$ox"
    local hx2=$((ox + w))
    local hy=$((oy + h + 18))
    local vx=$((ox - 16))
    local vy1="$oy"
    local vy2=$((oy + h))

    local label_w_x=$((ox + w / 2 - 28))
    local label_w_y=$((hy + 16))
    local label_h_x=8
    local label_h_y=$((oy + h / 2 + 4))

    local tmp png
    tmp="$(mktemp --suffix=.png)"
    png="$(mktemp --suffix=.png)"
    "$magick_bin" "$src" -type TrueColor -alpha off "PNG24:${tmp}"
    "$magick_bin" "$tmp" \
        -background white -gravity NorthWest \
        -extent "${new_w}x${new_h}-${left}-${top}" \
        -stroke black -strokewidth 1 -fill none \
        -draw "line ${hx1},${hy} ${hx2},${hy}" \
        -draw "line ${hx1},$((hy - tick)) ${hx1},$((hy + tick))" \
        -draw "line ${hx2},$((hy - tick)) ${hx2},$((hy + tick))" \
        -draw "line ${vx},${vy1} ${vx},${vy2}" \
        -draw "line $((vx - tick)),${vy1} $((vx + tick)),${vy1}" \
        -draw "line $((vx - tick)),${vy2} $((vx + tick)),${vy2}" \
        -fill black -stroke none \
        -font PT-Mono-Bold -pointsize 12 \
        -draw "text ${label_w_x},${label_w_y} '${cm_w} cm'" \
        -draw "text ${label_h_x},${label_h_y} '${cm_h} cm'" \
        "$png"
    "$magick_bin" "$png" -type Bilevel "pbm:${dest}"
    rm -f "$tmp" "$png"
}

draw_inward_frame() {
    local src="$1"
    local dest="$2"
    local w h
    read -r w h < <(im_identify -format '%w %h\n' "$src")
    local s="$FRAME_STROKE_PX"
    "$magick_bin" "$src" -type TrueColor -alpha off \
        -fill black \
        -draw "rectangle 0,0 $((w - 1)),$((s - 1))" \
        -draw "rectangle 0,$((h - s)) $((w - 1)),$((h - 1))" \
        -draw "rectangle 0,0 $((s - 1)),$((h - 1))" \
        -draw "rectangle $((w - s)),0 $((w - 1)),$((h - 1))" \
        -type Bilevel "pbm:${dest}"
}

apply_crop_frame() {
    local src="$1"
    local dest="$2"
    local w h
    read -r w h < <(im_identify -format '%w %h\n' "$src")
    local max_inner=$((MAX_WIDTH_PX - 2 * pad_px))
    [ "$max_inner" -gt 0 ] || die 'crop frame is larger than the printable width'
    local padded
    padded="$(mktemp --suffix=.png)"
    if [ $((w + 2 * pad_px)) -gt "$MAX_WIDTH_PX" ]; then
        printf 'warning: crop frame would exceed %s cm; shrinking the text box\n' \
            "$MAX_WIDTH_CM" >&2
        "$magick_bin" "$src" -resize "${max_inner}x" \
            -bordercolor white -border "$pad_px" "PNG24:${padded}"
    else
        "$magick_bin" "$src" -bordercolor white -border "$pad_px" "PNG24:${padded}"
    fi
    draw_inward_frame "$padded" "$dest"
    rm -f "$padded"
}

family_names() {
    fc-list --format='%{family}\n' "$@" 2>/dev/null \
        | awk -F',' '{
            name = $1
            sub(/[[:space:]]+$/, "", name)
            if (name != "" && name !~ /[Ee]moji|[Ss]ign[Ww]rit/) print name
        }' \
        | sort -u
}

font_is_installed() {
    local query="$1"
    local spaced="${query//-/ }"
    local candidate
    while IFS= read -r candidate; do
        [ "$candidate" = "$query" ] && return 0
        [ "$candidate" = "$spaced" ] && return 0
    done < <(family_names)
    im_font_exists "$query" && return 0
    im_font_exists "$spaced" && return 0
    return 1
}

font_search_matches() {
    local query="$1"
    local q="${query,,}"
    local candidate
    [ -n "$q" ] || return 0
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        if [[ "${candidate,,}" == *"$q"* ]]; then
            printf '%s\n' "$candidate"
        fi
    done < <(family_names)
}

face_names_for_family() {
    local family="$1"
    fc-list ":family=${family}" --format='%{fullname}|%{style}\n' 2>/dev/null \
        | awk -F'|' -v family="$family" '
            {
                full = $1
                style = $2
                sub(/,.*/, "", full)
                sub(/[[:space:]]+$/, "", full)
                sub(/^[[:space:]]+/, "", style)
                sub(/[[:space:]]+$/, "", style)
                if (style == "" || style == "Regular" || style == "Book" || style == "Normal") {
                    print family
                } else if (full != "") {
                    print full
                } else {
                    print family " " style
                }
            }
        ' | sort -u
}

font_face_fallback_search() {
    local query="$1"
    local q="${query,,}"
    local candidate
    [ -n "$q" ] || return 0
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        if [[ "${candidate,,}" == *"$q"* ]]; then
            printf '%s\n' "$candidate"
        fi
    done < <(
        fc-list --format='%{fullname}\n' 2>/dev/null \
            | awk -F',' '{
                name = $1
                sub(/[[:space:]]+$/, "", name)
                if (name != "" && name !~ /[Ee]moji|[Ss]ign[Ww]rit/) print name
            }'
        im_list_fonts 2>/dev/null | awk '
            $1 == "Font:" {
                n = $2
                gsub(/-/, " ", n)
                if (n != "") print n
            }
        '
    ) | sort -u
}

print_font_matches() {
    local i=1
    local name
    printf 'Matching fonts:\n'
    for name in "$@"; do
        printf '  %d) %s\n' "$i" "$name"
        i=$((i + 1))
    done
}

to_imagemagick_font() {
    local name="$1"
    if [ "$name" = 'Courier' ] || [ "$name" = 'Courier New' ]; then
        printf '%s\n' 'Courier'
        return
    fi
    printf '%s\n' "${name// /-}"
}

print_mono_helpers() {
    printf '\nMonospace fonts:\n'
    if [ "${#helpers[@]}" -eq 0 ]; then
        printf '  (none found)\n'
    else
        local i=1 name
        for name in "${helpers[@]}"; do
            printf '  %d) %s\n' "$i" "$name"
            i=$((i + 1))
        done
    fi
    printf '\n'
}

pick_font_from_matches() {
    local pick=""
    if [ "${#matches[@]}" -eq 0 ]; then
        return 1
    fi
    if [ "${#matches[@]}" -eq 1 ]; then
        font_name="${matches[0]}"
        return 0
    fi
    print_font_matches "${matches[@]}"
    prompt pick 'Font number: '
    case "$pick" in
        ''|*[!0-9]*)
            die "invalid font number: ${pick:-<empty>}"
            ;;
    esac
    [ "$pick" -ge 1 ] && [ "$pick" -le "${#matches[@]}" ] \
        || die "font number out of range: $pick"
    font_name="${matches[$((pick - 1))]}"
}

resolve_font_name() {
    local name=$1
    local allow_pick=${2:-}
    local matches=()
    local families=()
    local index
    case "$name" in
        [123])
            index=$((name - 1))
            [ "$index" -lt "${#helpers[@]}" ] || die "helper ${name} is not available"
            font_name="${helpers[$index]}"
            ;;
        *)
            if [ "$allow_pick" != pick ]; then
                font_is_installed "$name" || die "font is not installed: $name"
                font_name="$name"
                return
            fi
            mapfile -t families < <(font_search_matches "$name")
            if [ "${#families[@]}" -gt 1 ]; then
                matches=("${families[@]}")
                pick_font_from_matches
                return
            fi
            if [ "${#families[@]}" -eq 1 ]; then
                mapfile -t matches < <(face_names_for_family "${families[0]}")
                if [ "${#matches[@]}" -eq 0 ]; then
                    matches=("${families[0]}")
                fi
                pick_font_from_matches
                return
            fi
            mapfile -t matches < <(font_face_fallback_search "$name")
            pick_font_from_matches || die "font is not installed: $name"
            ;;
    esac
}

validate_font_size() {
    case "$1" in
        ''|*[!0-9]*)
            die "font size must be an integer, got: ${1:-<empty>}"
            ;;
    esac
    [ "$1" -gt 0 ] || die 'font size must be a positive integer'
}

validate_crop_mm() {
    case "$1" in
        ''|*[!0-9]*)
            die "crop frame inset must be an integer (millimeters), got: ${1:-<empty>}"
            ;;
    esac
    [ "$1" -gt 0 ] || die 'crop frame inset must be a positive integer (millimeters)'
}

validate_feed_mm() {
    case "$1" in
        ''|*[!0-9]*)
            die "feed must be a non-negative integer (millimeters), got: ${1:-<empty>}"
            ;;
    esac
}

set_crop_pad() {
    pad_px="$(cm_to_px "$(awk -v mm="$CROP_MM" 'BEGIN { printf "%.4f", mm / 10 }')")"
}

match_printer_model() {
    local name="$1"
    local model
    for model in "${PRINTER_MODELS[@]}"; do
        if [[ "$name" == "$model"* ]]; then
            printf '%s\n' "$model"
            return 0
        fi
    done
    return 1
}

list_bluez_devices() {
    local lines=""
    if ! command -v bluetoothctl >/dev/null 2>&1; then
        return 0
    fi
    lines="$(bluetoothctl devices Connected 2>/dev/null || true)"
    if [ -z "$lines" ]; then
        lines="$(bluetoothctl devices 2>/dev/null || true)"
    fi
    printf '%s\n' "$lines"
}

detect_printers() {
    found_macs=()
    found_models=()
    local line mac name model
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        [[ "$line" == Device\ * ]] || continue
        mac="$(printf '%s\n' "$line" | awk '{print $2}')"
        name="$(printf '%s\n' "$line" | awk '{ $1=""; $2=""; sub(/^  /, ""); print }')"
        model="$(match_printer_model "$name" || true)"
        [ -n "$model" ] || continue
        found_macs+=("$mac")
        found_models+=("$model")
    done < <(list_bluez_devices)
}

cli_text=""
cli_text_set=0
cli_fit=""
cli_fit_set=0
cli_font_size=""
cli_font=""
cli_real_sizes=""
cli_crop_frame=""
cli_feed=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --text)
            [ $# -ge 2 ] || die "$1 requires a value (try --help)"
            cli_text=$2
            cli_text_set=1
            shift 2
            ;;
        --fit)
            require_arg "$1" "${2-}"
            cli_fit=$2
            cli_fit_set=1
            shift 2
            ;;
        --font-size)
            require_arg "$1" "${2-}"
            cli_font_size=$2
            shift 2
            ;;
        --font)
            require_arg "$1" "${2-}"
            cli_font=$2
            shift 2
            ;;
        --real-sizes)
            cli_real_sizes=1
            shift
            ;;
        --no-real-sizes)
            cli_real_sizes=0
            shift
            ;;
        --crop-frame)
            cli_crop_frame=1
            shift
            ;;
        --no-crop-frame)
            cli_crop_frame=0
            shift
            ;;
        --feed)
            require_arg "$1" "${2-}"
            cli_feed=$2
            shift 2
            ;;
        *)
            die "unknown option: $1 (try --help)"
            ;;
    esac
done

if [ "$cli_fit_set" -eq 1 ] && [ -n "$cli_font_size" ]; then
    die '--fit cannot be used with --font-size'
fi

feed_mm="$DEFAULT_FEED_MM"
if [ -n "$cli_feed" ]; then
    validate_feed_mm "$cli_feed"
    feed_mm="$cli_feed"
fi

require_imagemagick
require_cat_printer
command -v fc-list >/dev/null 2>&1 || die 'fc-list not found (install fontconfig)'

mapfile -t all_mono < <(family_names ':spacing=mono')
preferred=(
    'PT Mono Bold'
    'Courier'
    'Ubuntu Mono'
    'Ubuntu Sans Mono'
    'Liberation Mono'
    'Nimbus Mono PS'
    'FreeMono'
    'Noto Mono'
)

helpers=()
for name in "${preferred[@]}"; do
    [ "${#helpers[@]}" -eq 3 ] && break
    if [ "$name" = 'Courier' ] || [ "$name" = 'PT Mono Bold' ]; then
        im_font_exists "$name" || continue
        helpers+=("$name")
        continue
    fi
    for installed in "${all_mono[@]+"${all_mono[@]}"}"; do
        if [ "$installed" = "$name" ]; then
            helpers+=("$name")
            break
        fi
    done
done

if [ "${#helpers[@]}" -lt 3 ]; then
    for installed in "${all_mono[@]+"${all_mono[@]}"}"; do
        [ "${#helpers[@]}" -eq 3 ] && break
        already=0
        for picked in "${helpers[@]+"${helpers[@]}"}"; do
            [ "$picked" = "$installed" ] && already=1 && break
        done
        [ "$already" -eq 0 ] && helpers+=("$installed")
    done
fi

default_font="${helpers[0]:-PT Mono Bold}"

text=""
if [ "$cli_text_set" -eq 1 ]; then
    text="$cli_text"
elif [ ! -t 0 ]; then
    text="$(cat || true)"
else
    prompt text 'Text to preview [Hello World]: '
fi
text="${text%"${text##*[![:space:]]}"}"
text="${text#"${text%%[![:space:]]*}"}"
[ -n "$text" ] || text="$DEFAULT_TEXT"

font_name=""
if [ -n "$cli_font" ]; then
    resolve_font_name "$cli_font"
elif has_tty; then
    print_mono_helpers
    prompt font_name "Font name (or 1-3, substring) [${default_font}]: "
    if [ -n "$font_name" ]; then
        resolve_font_name "$font_name" pick
    else
        font_name="$default_font"
    fi
else
    font_name="$default_font"
fi
im_font="$(to_imagemagick_font "$font_name")"

fit_spec=""
if [ "$cli_fit_set" -eq 1 ]; then
    fit_spec="$cli_fit"
elif [ -n "$cli_font_size" ]; then
    fit_spec=""
elif has_tty; then
    prompt fit_spec 'Fit size in cm (final size if crop frame; max 4.88; e.g. 4:2.5, 4, :2.5, empty to skip): '
else
    fit_spec=""
fi

fit_w_px=""
fit_h_px=""
use_fit=0
if [ -n "$fit_spec" ]; then
    parse_fit "$fit_spec"
    use_fit=1
fi

font_size=""
if [ "$use_fit" -eq 0 ]; then
    if [ -n "$cli_font_size" ]; then
        font_size="$cli_font_size"
    elif has_tty; then
        prompt font_size "Font size (px) [${DEFAULT_FONT_SIZE}]: "
        [ -n "$font_size" ] || font_size="$DEFAULT_FONT_SIZE"
    else
        font_size="$DEFAULT_FONT_SIZE"
    fi
    validate_font_size "$font_size"
fi

show_sizes=""
if [ -n "$cli_real_sizes" ]; then
    show_sizes="$cli_real_sizes"
else
    prompt_yn show_sizes 'Show real sizes [Y/n]: '
fi

crop_frame=""
if [ -n "$cli_crop_frame" ]; then
    crop_frame="$cli_crop_frame"
else
    prompt_yn crop_frame 'Add a crop frame (5 mm from text, 3 px inward) [Y/n]: '
    if [ "$crop_frame" -eq 1 ] && has_tty; then
        printf '%s\n' 'Enter an integer in millimeters.'
        crop_mm_in=""
        prompt crop_mm_in "Crop frame inset (mm) [${CROP_MM}]: "
        if [ -n "$crop_mm_in" ]; then
            validate_crop_mm "$crop_mm_in"
            CROP_MM="$crop_mm_in"
        fi
    fi
fi
set_crop_pad

if [ "$use_fit" -eq 1 ] && [ "$crop_frame" -eq 1 ]; then
    reserve_crop_in_fit
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
clean_pbm="$work_dir/dump.pbm"
print_pbm="$clean_pbm"

if [ "$use_fit" -eq 1 ]; then
    geom=""
    caption_max_w="$MAX_WIDTH_PX"
    if [ "$crop_frame" -eq 1 ]; then
        caption_max_w=$((MAX_WIDTH_PX - 2 * pad_px))
    fi
    if [ -n "$fit_w_px" ] && [ -n "$fit_h_px" ]; then
        geom="${fit_w_px}x${fit_h_px}"
    elif [ -n "$fit_w_px" ]; then
        geom="${fit_w_px}x"
    else
        geom="${caption_max_w}x${fit_h_px}"
    fi
    "$magick_bin" -background white -fill black \
        -size "$geom" -font "$im_font" \
        "caption:$(escape_caption "$text")" \
        "pbm:${clean_pbm}"
    estimated_px="$(estimate_fit_pointsize "$im_font" "$text" "$fit_w_px" "$fit_h_px")"
else
    geom="${MAX_WIDTH_PX}x"
    "$magick_bin" -background white -fill black \
        -size "$geom" -pointsize "$font_size" -font "$im_font" \
        "caption:$(escape_caption "$text")" \
        "pbm:${clean_pbm}"
    estimated_px=""
fi

if [ "$crop_frame" -eq 1 ]; then
    print_pbm="$work_dir/framed.pbm"
    apply_crop_frame "$clean_pbm" "$print_pbm"
fi

preview_src="$print_pbm"
if [ "$show_sizes" -eq 1 ]; then
    preview_src="$work_dir/annotated.pbm"
    annotate_real_sizes "$print_pbm" "$preview_src"
fi

mkdir -p /tmp/cat-printer
preview_file="/tmp/cat-printer/preview_$(date +%Y_%m_%d_%H_%M_%S).pbm"
cp "$preview_src" "$preview_file"

if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$preview_file" >/dev/null 2>&1 || true
fi

printf '%s\n' "$preview_file"
if [ -n "$estimated_px" ]; then
    printf 'Estimated font size: %s px\n' "$estimated_px"
fi

found_macs=()
found_models=()
detect_printers
scan_model='MX10'
scan_mac="$PLACEHOLDER_MAC"
if [ "${#found_macs[@]}" -eq 1 ]; then
    scan_model="${found_models[0]}"
    scan_mac="${found_macs[0]}"
elif [ "${#found_macs[@]}" -gt 1 ]; then
    printf 'Printer MACs:\n'
    local_i=0
    for local_i in "${!found_macs[@]}"; do
        printf '%s %s\n' "${found_models[$local_i]}" "${found_macs[$local_i]}"
    done
    printf 'Replace %s with one of the MACs above\n' "$PLACEHOLDER_MAC" >&2
else
    printf 'Replace %s with the printer MAC\n' "$PLACEHOLDER_MAC" >&2
fi
scan_arg="4,${scan_model},${scan_mac}"

quoted_text="$(shell_quote "$text")"
quoted_font="$(shell_quote "$im_font")"
magick_name="$(basename "$magick_bin")"
printf 'Command for direct printing:\n'
if [ "$use_fit" -eq 1 ] || [ "$crop_frame" -eq 1 ]; then
    if [ "$use_fit" -eq 1 ]; then
        render_cmd="$magick_name -background white -fill black -size $geom -font $quoted_font caption:$quoted_text"
    else
        render_cmd="$magick_name -background white -fill black -size $geom -pointsize $font_size -font $quoted_font caption:$quoted_text"
    fi
    if [ "$crop_frame" -eq 1 ]; then
        fw=""
        fh=""
        read -r fw fh < <(im_identify -format '%w %h\n' "$print_pbm")
        inner_w=$((fw - 2 * pad_px))
        orig_w=""
        read -r orig_w _ < <(im_identify -format '%w %h\n' "$clean_pbm")
        if [ $((orig_w + 2 * pad_px)) -gt "$MAX_WIDTH_PX" ]; then
            render_cmd+=" -resize ${inner_w}x"
        fi
        s="$FRAME_STROKE_PX"
        render_cmd+=" -bordercolor white -border ${pad_px}"
        render_cmd+=" -fill black"
        render_cmd+=" -draw $(shell_quote "rectangle 0,0 $((fw - 1)),$((s - 1))")"
        render_cmd+=" -draw $(shell_quote "rectangle 0,$((fh - s)) $((fw - 1)),$((fh - 1))")"
        render_cmd+=" -draw $(shell_quote "rectangle 0,0 $((s - 1)),$((fh - 1))")"
        render_cmd+=" -draw $(shell_quote "rectangle $((fw - s)),0 $((fw - 1)),$((fh - 1))")"
    fi
    printf '%s pbm:- | %s -s %s --feed %s -\n' \
        "$render_cmd" \
        "$print_cmd_display" \
        "$scan_arg" \
        "$feed_mm"
else
    printf 'echo %s | %s -s %s --feed %s -t %s,%s -\n' \
        "$quoted_text" \
        "$print_cmd_display" \
        "$scan_arg" \
        "$feed_mm" \
        "$font_size" \
        "$im_font"
fi
