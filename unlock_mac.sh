#!/bin/bash
# Xiaomi QC bootloader unlock — macOS
# Supports: 8E5 / 8E / 8SGen4 / 8Gen3 / 8SGen3 / 8Gen2
# Requires: adb, fastboot (brew install android-platform-tools)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD_DIR="$SCRIPT_DIR/payloads"
ADB="adb"
FASTBOOT="fastboot"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
fail()  { echo -e "${RED}[-]${NC} $1"; exit 1; }

wait_adb() {
    info "Waiting for ADB device..."
    $ADB wait-for-device
    sleep 1
    ok "ADB device connected"
}

wait_fastboot() {
    info "Waiting for fastboot device..."
    local count=0
    while ! $FASTBOOT devices 2>&1 | grep -q "fastboot"; do
        sleep 1
        count=$((count + 1))
        if [ $count -ge 120 ]; then
            fail "Timed out waiting for fastboot device"
        fi
    done
    ok "Fastboot device connected"
}

prop() {
    $ADB shell getprop "$1" 2>/dev/null | tr -d '\r\n'
}

# =============================================
# Device detection
# =============================================
detect_device() {
    MODEL=$(prop ro.product.marketname)
    CODENAME=$(prop ro.product.board)
    SYSTEM=$(prop ro.build.display.id)
    PATCH=$(prop ro.vendor.build.security_patch)
    KERNEL=$($ADB shell uname -r 2>/dev/null | tr -d '\r\n')
    SOC=$(prop ro.hardware.chipname)
    [ -z "$SOC" ] && SOC=$(prop ro.board.platform)

    echo ""
    info "Model:          $MODEL"
    info "Codename:       $CODENAME"
    info "System:         $SYSTEM"
    info "Security patch: $PATCH"
    info "Kernel:         $KERNEL"
    info "SoC:            $SOC"
    echo ""
}

# =============================================
# Chipset identification
# =============================================
identify_chipset() {
    CHIPSET=""
    case "$CODENAME" in
        # 8E5 - Xiaomi 17 series
        nezha|manet|diana|hanuman|draco)
            CHIPSET="8e5" ;;
        # 8E - Xiaomi 15 series, K80 Pro, K90, K90 Ultra, MIX Flip 2, Pad 8 Pro
        dada|shennong|dijia|haotian|K80Pro|duanmu|K90Ultra|mixFlip2|Pad8Pro)
            CHIPSET="8e" ;;
        # 8SGen4 - Turbo 4 Pro, Civi 5 Pro, Pad 8
        peridot|civi5pro|xiaomiPad8)
            CHIPSET="8sgen4" ;;
        # 8Gen3 - Xiaomi 14 series, K70 Pro, K80, MIX Flip, MIX Fold 4
        houji|shennong14|aurora|goku|K70Pro|K80|mixFlip|mixFold4)
            CHIPSET="8gen3" ;;
        # 8SGen3 - Turbo 3, Civi 4 Pro, Pad 7/7Pro
        peridot3|civi4pro|xiaomiPad7|xiaomiPad7Pro)
            CHIPSET="8sgen3" ;;
        # 8Gen2 - Xiaomi 13 series, K60 Pro, K70, Pad 6S Pro, MIX Fold 3
        fuxi|nuwa|ishtar|K60Pro|K70|Pad6SPro|mixFold3)
            CHIPSET="8gen2" ;;
    esac

    if [ -z "$CHIPSET" ]; then
        case "$SOC" in
            *8850*|*8e5*) CHIPSET="8e5" ;;
            *8750*|*sun*) CHIPSET="8e" ;;
            *8735*)       CHIPSET="8sgen4" ;;
            *8650*|*pineapple*) CHIPSET="8gen3" ;;
            *8635*|*7675*) CHIPSET="8sgen3" ;;
            *8550*|*kalama*) CHIPSET="8gen2" ;;
        esac
    fi

    if [ -z "$CHIPSET" ]; then
        echo ""
        warn "Cannot auto-detect chipset for: $MODEL ($CODENAME / $SOC)"
        echo ""
        echo "  1) 8E5  - Xiaomi 17 / 17 Pro / 17 Pro Max / 17 Ultra / K90 Pro Max"
        echo "  2) 8E   - Xiaomi 15 / 15 Pro / 15 Ultra / K80 Pro / K90 / K90 Ultra / MIX Flip 2 / Pad 8 Pro"
        echo "  3) 8SGen4 - Redmi Turbo 4 Pro / Civi 5 Pro / Pad 8"
        echo "  4) 8Gen3 - Xiaomi 14 / 14 Pro / 14 Ultra / K70 Pro / K80 / MIX Flip / MIX Fold 4"
        echo "  5) 8SGen3 - Redmi Turbo 3 / Civi 4 Pro / Pad 7 / Pad 7 Pro"
        echo "  6) 8Gen2 - Xiaomi 13 / 13 Pro / 13 Ultra / K60 Pro / K70 / Pad 6S Pro / MIX Fold 3"
        echo ""
        read -rp "Select chipset (1-6): " choice
        case "$choice" in
            1) CHIPSET="8e5" ;;
            2) CHIPSET="8e" ;;
            3) CHIPSET="8sgen4" ;;
            4) CHIPSET="8gen3" ;;
            5) CHIPSET="8sgen3" ;;
            6) CHIPSET="8gen2" ;;
            *) fail "Invalid choice" ;;
        esac
    fi

    ok "Chipset: $CHIPSET"
}

# =============================================
# Select exploit payload
# =============================================
select_exploit() {
    EXPLOIT_FILE=""
    EXPLOIT_TYPE=""

    case "$CHIPSET" in
        8e5)
            EXPLOIT_TYPE="preload"
            if [[ "$KERNEL" == 6.12.69* ]]; then
                EXPLOIT_FILE="$PAYLOAD_DIR/8e5/preload_Mi_8E5_A17_6.12.69.so"
            elif [[ "$KERNEL" == 6.12.23* ]]; then
                # Check global ROM variant
                local region
                region=$(prop ro.product.mod_device)
                if [[ "$region" == *"_global"* ]]; then
                    EXPLOIT_FILE="$PAYLOAD_DIR/8e5/preload_Mi_8E5_GL_A16_6.12.23.so"
                else
                    EXPLOIT_FILE="$PAYLOAD_DIR/8e5/preload_Mi_8E5_A16_6.12.23.so"
                fi
            fi
            ;;
        8e)
            EXPLOIT_TYPE="preload"
            if [[ "$KERNEL" == 6.6.118* ]]; then
                case "$MODEL" in
                    *"K90 Ultra"*|*"K90Ultra"*)
                        EXPLOIT_FILE="$PAYLOAD_DIR/8e/SELinux/preload_k90u_302_303_6.6.118.so"
                        ;;
                    *"K90"*|*"K90U"*)
                        EXPLOIT_FILE="$PAYLOAD_DIR/8e/SELinux/preload_k90_k90u_6.6.118.so"
                        ;;
                    *"K80"*|*"Pad 8"*|*"Pad8"*)
                        EXPLOIT_FILE="$PAYLOAD_DIR/8e/SELinux/preload_k80p_Pad8p_6.6.118.so"
                        ;;
                    *)
                        EXPLOIT_FILE="$PAYLOAD_DIR/8e/SELinux/preload_k80p_Pad8p_6.6.118.so"
                        ;;
                esac
            elif [[ "$KERNEL" == 6.6.77* ]]; then
                case "$MODEL" in
                    *"Flip"*|*"K90"*)
                        EXPLOIT_FILE="$PAYLOAD_DIR/8e/SELinux/preload_Flip2_k90_6.6.77.so"
                        ;;
                    *)
                        EXPLOIT_FILE="$PAYLOAD_DIR/8e/SELinux/preload_15p_15u_k80p_6.6.77.so"
                        ;;
                esac
            fi
            ;;
        8sgen4)
            EXPLOIT_TYPE="preload"
            if [[ "$KERNEL" == 6.6.118* ]]; then
                EXPLOIT_FILE="$PAYLOAD_DIR/8sgen4/SELinux/preload_Mi_8SGen4_6.6.118.so"
            elif [[ "$KERNEL" == 6.6.77* ]]; then
                EXPLOIT_FILE="$PAYLOAD_DIR/8sgen4/SELinux/preload_Mi_8SGen4_6.6.77.so"
            fi
            ;;
        8gen3)
            EXPLOIT_TYPE="standalone"
            case "$MODEL" in
                *"K80"*|*"K70"*)
                    EXPLOIT_FILE="$PAYLOAD_DIR/8gen3/SELinux/k80_exploit"
                    ;;
                *)
                    EXPLOIT_FILE="$PAYLOAD_DIR/8gen3/SELinux/mi14_exploit"
                    ;;
            esac
            ;;
        8sgen3)
            EXPLOIT_TYPE="standalone"
            case "$MODEL" in
                *"Pad 7 Pro"*|*"Pad7Pro"*)
                    # Check security patch for May variant
                    if [[ "$PATCH" > "2026-04" ]]; then
                        EXPLOIT_FILE="$PAYLOAD_DIR/8sgen3/SELinux/exploit_Pad7Pro_May"
                    else
                        EXPLOIT_FILE="$PAYLOAD_DIR/8sgen3/SELinux/exploit_Pad7Pro"
                    fi
                    ;;
                *"Pad 7"*|*"Pad7"*)
                    EXPLOIT_FILE="$PAYLOAD_DIR/8sgen3/SELinux/exploit_Pad7"
                    ;;
                *)
                    EXPLOIT_FILE="$PAYLOAD_DIR/8sgen3/SELinux/exploit_Pad7"
                    ;;
            esac
            ;;
        8gen2)
            EXPLOIT_TYPE="none"
            warn "8Gen2 has no bundled exploit."
            warn "You must obtain root + SELinux permissive on your own."
            warn "After achieving root, re-run this tool."
            echo ""
            read -rp "Is SELinux already permissive? (y/n): " perm
            if [[ "$perm" != "y" ]]; then
                fail "Cannot proceed without root + SELinux permissive on 8Gen2"
            fi
            ;;
    esac

    if [[ "$EXPLOIT_TYPE" != "none" ]]; then
        if [[ -z "$EXPLOIT_FILE" ]]; then
            warn "No matching exploit for kernel $KERNEL"
            echo ""
            echo "Available exploits:"
            case "$CHIPSET" in
                8e5) find "$PAYLOAD_DIR/8e5" -name "preload_*.so" -exec basename {} \; ;;
                8e)  find "$PAYLOAD_DIR/8e/SELinux" -name "preload_*.so" -exec basename {} \; ;;
                8sgen4) find "$PAYLOAD_DIR/8sgen4/SELinux" -name "preload_*.so" -exec basename {} \; ;;
                8gen3)  find "$PAYLOAD_DIR/8gen3/SELinux" -name "*_exploit" -exec basename {} \; ;;
                8sgen3) find "$PAYLOAD_DIR/8sgen3/SELinux" -name "exploit_*" -exec basename {} \; ;;
            esac
            echo ""
            read -rp "Enter filename to use: " custom
            case "$CHIPSET" in
                8e5) EXPLOIT_FILE="$PAYLOAD_DIR/8e5/$custom" ;;
                8e|8sgen4) EXPLOIT_FILE="$PAYLOAD_DIR/$CHIPSET/SELinux/$custom" ;;
                8gen3|8sgen3) EXPLOIT_FILE="$PAYLOAD_DIR/$CHIPSET/SELinux/$custom" ;;
            esac
        fi

        [ -f "$EXPLOIT_FILE" ] || fail "Exploit file not found: $EXPLOIT_FILE"
        ok "Exploit: $(basename "$EXPLOIT_FILE")"
    fi
}

# =============================================
# Select ABL (old/factory)
# =============================================
select_abl() {
    ABL_FILE=""

    case "$CHIPSET" in
        8e5)
            case "$MODEL" in
                *"17 Ultra"*|*"17Ultra"*)   ABL_FILE="$PAYLOAD_DIR/8e5/old_abl/mi17Ultra_abl.elf" ;;
                *"17 Pro Max"*|*"17ProMax"*) ABL_FILE="$PAYLOAD_DIR/8e5/old_abl/mi17ProMax_abl.elf" ;;
                *"17 Pro"*|*"17Pro"*)       ABL_FILE="$PAYLOAD_DIR/8e5/old_abl/mi17Pro_abl.elf" ;;
                *"17"*)                     ABL_FILE="$PAYLOAD_DIR/8e5/old_abl/mi17_abl.elf" ;;
                *"K90"*)                    ABL_FILE="$PAYLOAD_DIR/8e5/old_abl/K90ProMax_abl.elf" ;;
            esac
            ;;
        8e)
            case "$MODEL" in
                *"K90 Ultra"*|*"K90Ultra"*) ABL_FILE="$PAYLOAD_DIR/8e/K90Ultra_old_abl.elf" ;;
                *"K90"*)                    ABL_FILE="$PAYLOAD_DIR/8e/Factory_abl/K90_abl.elf" ;;
                *"K80"*)                    ABL_FILE="$PAYLOAD_DIR/8e/Factory_abl/K80Pro_abl.elf" ;;
                *"15 Ultra"*|*"15Ultra"*)   ABL_FILE="$PAYLOAD_DIR/8e/Factory_abl/mi15Ultra_abl.elf" ;;
                *"15 Pro"*|*"15Pro"*)       ABL_FILE="$PAYLOAD_DIR/8e/Factory_abl/mi15Pro_abl.elf" ;;
                *"15"*)                     ABL_FILE="$PAYLOAD_DIR/8e/Factory_abl/mi15_abl.elf" ;;
                *"Flip"*)                   ABL_FILE="$PAYLOAD_DIR/8e/Factory_abl/mix_Flip2.elf" ;;
                *"Pad"*)                    ABL_FILE="$PAYLOAD_DIR/8e/Factory_abl/Pad8Pro.elf" ;;
            esac
            ;;
        8sgen4)
            case "$MODEL" in
                *"Turbo"*)  ABL_FILE="$PAYLOAD_DIR/8sgen4/Factory_abl/Redmi_Turbo4Pro_abl.elf" ;;
                *"Civi"*)   ABL_FILE="$PAYLOAD_DIR/8sgen4/Factory_abl/Xiaomi_Civi5Pro_abl.elf" ;;
                *"Pad"*)    ABL_FILE="$PAYLOAD_DIR/8sgen4/Factory_abl/Xiaomi_Pad8_abl.elf" ;;
            esac
            ;;
        8gen3)
            case "$MODEL" in
                *"K70"*)                    ABL_FILE="$PAYLOAD_DIR/8gen3/Factory_abl/K70Pro_abl.elf" ;;
                *"K80"*)                    ABL_FILE="$PAYLOAD_DIR/8gen3/Factory_abl/K80_abl.elf" ;;
                *"14 Ultra"*|*"14Ultra"*)   ABL_FILE="$PAYLOAD_DIR/8gen3/Factory_abl/mi14Ultra_abl.elf" ;;
                *"14 Pro"*|*"14Pro"*)       ABL_FILE="$PAYLOAD_DIR/8gen3/Factory_abl/mi14Pro_abl.elf" ;;
                *"14"*)                     ABL_FILE="$PAYLOAD_DIR/8gen3/Factory_abl/mi14_abl.elf" ;;
                *"Flip"*)                   ABL_FILE="$PAYLOAD_DIR/8gen3/Factory_abl/mix_Flip_abl.elf" ;;
                *"Fold"*)                   ABL_FILE="$PAYLOAD_DIR/8gen3/Factory_abl/mix_Fold4_abl.elf" ;;
            esac
            ;;
        8sgen3)
            case "$MODEL" in
                *"Turbo"*)               ABL_FILE="$PAYLOAD_DIR/8sgen3/Factory_abl/Redmi_Turbo3_abl.elf" ;;
                *"Civi"*)                ABL_FILE="$PAYLOAD_DIR/8sgen3/Factory_abl/Xiaomi_Civi4Pro_abl.elf" ;;
                *"Pad 7 Pro"*|*"Pad7Pro"*) ABL_FILE="$PAYLOAD_DIR/8sgen3/Factory_abl/Xiaomi_Pad7Pro_abl.elf" ;;
                *"Pad 7"*|*"Pad7"*)      ABL_FILE="$PAYLOAD_DIR/8sgen3/Factory_abl/Xiaomi_Pad7_abl.elf" ;;
            esac
            ;;
        8gen2)
            case "$MODEL" in
                *"K60"*)                    ABL_FILE="$PAYLOAD_DIR/8gen2/Factory_abl/K60Pro_abl.elf" ;;
                *"K70"*)                    ABL_FILE="$PAYLOAD_DIR/8gen2/Factory_abl/K70_abl.elf" ;;
                *"Pad"*)                    ABL_FILE="$PAYLOAD_DIR/8gen2/Factory_abl/Pad6SPro_abl.elf" ;;
                *"13 Ultra"*|*"13Ultra"*)   ABL_FILE="$PAYLOAD_DIR/8gen2/Factory_abl/mi13Ultra_abl.elf" ;;
                *"13 Pro"*|*"13Pro"*)       ABL_FILE="$PAYLOAD_DIR/8gen2/Factory_abl/mi13Pro_abl.elf" ;;
                *"13"*)                     ABL_FILE="$PAYLOAD_DIR/8gen2/Factory_abl/mi13_abl.elf" ;;
                *"Fold"*)                   ABL_FILE="$PAYLOAD_DIR/8gen2/Factory_abl/mix_Fold3_abl.elf" ;;
            esac
            ;;
    esac

    if [ -z "$ABL_FILE" ]; then
        warn "Cannot auto-select ABL for: $MODEL"
        echo "Available ABLs:"
        case "$CHIPSET" in
            8e5) ls "$PAYLOAD_DIR/8e5/old_abl/" ;;
            8e)  ls "$PAYLOAD_DIR/8e/Factory_abl/" ; echo "K90Ultra_old_abl.elf" ;;
            *)   ls "$PAYLOAD_DIR/$CHIPSET/Factory_abl/" ;;
        esac
        echo ""
        read -rp "Enter ABL filename: " custom_abl
        case "$CHIPSET" in
            8e5) ABL_FILE="$PAYLOAD_DIR/8e5/old_abl/$custom_abl" ;;
            8e)
                if [[ "$custom_abl" == *"K90Ultra"* ]]; then
                    ABL_FILE="$PAYLOAD_DIR/8e/$custom_abl"
                else
                    ABL_FILE="$PAYLOAD_DIR/8e/Factory_abl/$custom_abl"
                fi
                ;;
            *) ABL_FILE="$PAYLOAD_DIR/$CHIPSET/Factory_abl/$custom_abl" ;;
        esac
    fi

    [ -f "$ABL_FILE" ] || fail "ABL file not found: $ABL_FILE"
    ok "ABL: $(basename "$ABL_FILE")"
}

# =============================================
# Select GPT and unlock boot (non-8E5 only)
# =============================================
select_gpt_and_boot() {
    GPT_BOTH4=""
    UNLOCK_BOOT=""
    GPT_RESTORE_DIR=""

    if [ "$CHIPSET" = "8e5" ]; then
        return
    fi

    # Select modified gpt_both4
    case "$CHIPSET" in
        8e)
            case "$MODEL" in
                *"Pad"*) GPT_BOTH4="$PAYLOAD_DIR/8e/Pad8Pro_gpt_both4.bin" ;;
                *)       GPT_BOTH4="$PAYLOAD_DIR/8e/Xiaomi_8e_gpt_both4.bin" ;;
            esac
            ;;
        8sgen4)
            case "$MODEL" in
                *"Turbo"*) GPT_BOTH4="$PAYLOAD_DIR/8sgen4/Turbo4Pro_gpt_both4.bin" ;;
                *"Civi"*)  GPT_BOTH4="$PAYLOAD_DIR/8sgen4/Mi_Civi5Pro_gpt_both4.bin" ;;
                *"Pad"*)   GPT_BOTH4="$PAYLOAD_DIR/8sgen4/Mi_Pad8_gpt_both4.bin" ;;
            esac
            ;;
        8gen3)
            case "$MODEL" in
                *"K70"*)  GPT_BOTH4="$PAYLOAD_DIR/8gen3/K70Pro_gpt_both4.bin" ;;
                *"K80"*)  GPT_BOTH4="$PAYLOAD_DIR/8gen3/K80_gpt_both4.bin" ;;
                *"14 Ultra"*|*"14Ultra"*) GPT_BOTH4="$PAYLOAD_DIR/8gen3/mi14Ultra_gpt_both4.bin" ;;
                *"14 Pro"*|*"14Pro"*)     GPT_BOTH4="$PAYLOAD_DIR/8gen3/mi14Pro_gpt_both4.bin" ;;
                *"14"*)                   GPT_BOTH4="$PAYLOAD_DIR/8gen3/mi14_gpt_both4.bin" ;;
                *"Flip"*)                 GPT_BOTH4="$PAYLOAD_DIR/8gen3/mix_Flip_gpt_both4.bin" ;;
                *"Fold"*)                 GPT_BOTH4="$PAYLOAD_DIR/8gen3/mix_Fold4_gpt_both4.bin" ;;
            esac
            ;;
        8sgen3)
            case "$MODEL" in
                *"Turbo"*) GPT_BOTH4="$PAYLOAD_DIR/8sgen3/Turbo3_gpt_both4.bin" ;;
                *"Civi"*)  GPT_BOTH4="$PAYLOAD_DIR/8sgen3/Mi_Civi4Pro_gpt_both4.bin" ;;
                *"Pad 7 Pro"*|*"Pad7Pro"*) GPT_BOTH4="$PAYLOAD_DIR/8sgen3/Mi_Pad7Pro_gpt_both4.bin" ;;
                *"Pad 7"*|*"Pad7"*)        GPT_BOTH4="$PAYLOAD_DIR/8sgen3/Mi_Pad7_gpt_both4.bin" ;;
            esac
            ;;
        8gen2)
            case "$MODEL" in
                *"K60"*)  GPT_BOTH4="$PAYLOAD_DIR/8gen2/K60Pro_gpt_both4.bin" ;;
                *"K70"*)  GPT_BOTH4="$PAYLOAD_DIR/8gen2/K70_gpt_both4.bin" ;;
                *"Pad"*)  GPT_BOTH4="$PAYLOAD_DIR/8gen2/Pad6SPro_gpt_both4.bin" ;;
                *"13 Ultra"*|*"13Ultra"*) GPT_BOTH4="$PAYLOAD_DIR/8gen2/mi13Ultra_gpt_both4.bin" ;;
                *"13 Pro"*|*"13Pro"*)     GPT_BOTH4="$PAYLOAD_DIR/8gen2/mi13Pro_gpt_both4.bin" ;;
                *"13"*)                   GPT_BOTH4="$PAYLOAD_DIR/8gen2/mi13_gpt_both4.bin" ;;
                *"Fold"*)                 GPT_BOTH4="$PAYLOAD_DIR/8gen2/mix_Fold3_gpt_both4.bin" ;;
            esac
            ;;
    esac

    if [ -n "$GPT_BOTH4" ] && [ -f "$GPT_BOTH4" ]; then
        ok "GPT:  $(basename "$GPT_BOTH4")"
    else
        warn "Cannot auto-select gpt_both4 for: $MODEL"
        echo "Available gpt_both4 files:"
        ls "$PAYLOAD_DIR/$CHIPSET/"*gpt_both4.bin 2>/dev/null
        echo ""
        read -rp "Enter gpt_both4 filename: " custom_gpt
        GPT_BOTH4="$PAYLOAD_DIR/$CHIPSET/$custom_gpt"
        [ -f "$GPT_BOTH4" ] || fail "GPT file not found: $GPT_BOTH4"
    fi

    # Select official gpt_both restore directory
    case "$CHIPSET" in
        8e)
            case "$MODEL" in
                *"K80"*)   GPT_RESTORE_DIR="$PAYLOAD_DIR/8e/official-gpt_both/RedmiK80Pro" ;;
                *"K90 Ultra"*|*"K90Ultra"*) GPT_RESTORE_DIR="$PAYLOAD_DIR/8e/official-gpt_both/RedmiK90Ultra" ;;
                *"K90"*)   GPT_RESTORE_DIR="$PAYLOAD_DIR/8e/official-gpt_both/RedmiK90" ;;
                *"15 Ultra"*|*"15Ultra"*) GPT_RESTORE_DIR="$PAYLOAD_DIR/8e/official-gpt_both/Xiaomi15Ultra" ;;
                *"15 Pro"*|*"15Pro"*)     GPT_RESTORE_DIR="$PAYLOAD_DIR/8e/official-gpt_both/Xiaomi15Pro" ;;
                *"15"*)                   GPT_RESTORE_DIR="$PAYLOAD_DIR/8e/official-gpt_both/Xiaomi15" ;;
                *"Flip"*)                 GPT_RESTORE_DIR="$PAYLOAD_DIR/8e/official-gpt_both/Xiaomi_MIX_Flip2" ;;
                *"Pad"*)                  GPT_RESTORE_DIR="$PAYLOAD_DIR/8e/official-gpt_both/XiaomiPad8Pro" ;;
            esac
            ;;
        8sgen4)
            case "$MODEL" in
                *"Turbo"*) GPT_RESTORE_DIR="$PAYLOAD_DIR/8sgen4/official-gpt_both/Redmi_Turbo4Pro" ;;
                *"Civi"*)  GPT_RESTORE_DIR="$PAYLOAD_DIR/8sgen4/official-gpt_both/Xiaomi_Civi5Pro" ;;
                *"Pad"*)   GPT_RESTORE_DIR="$PAYLOAD_DIR/8sgen4/official-gpt_both/Xiaomi_Pad8" ;;
            esac
            ;;
        8gen3)
            case "$MODEL" in
                *"K70"*)  GPT_RESTORE_DIR="$PAYLOAD_DIR/8gen3/official-gpt_both/RedmiK70Pro" ;;
                *"K80"*)  GPT_RESTORE_DIR="$PAYLOAD_DIR/8gen3/official-gpt_both/RedmiK80" ;;
                *"14 Ultra"*|*"14Ultra"*) GPT_RESTORE_DIR="$PAYLOAD_DIR/8gen3/official-gpt_both/Xiaomi14Ultra" ;;
                *"14 Pro"*|*"14Pro"*)     GPT_RESTORE_DIR="$PAYLOAD_DIR/8gen3/official-gpt_both/Xiaomi14Pro" ;;
                *"14"*)                   GPT_RESTORE_DIR="$PAYLOAD_DIR/8gen3/official-gpt_both/Xiaomi14" ;;
                *"Flip"*)                 GPT_RESTORE_DIR="$PAYLOAD_DIR/8gen3/official-gpt_both/Xiaomi_MIX_Flip" ;;
                *"Fold"*)                 GPT_RESTORE_DIR="$PAYLOAD_DIR/8gen3/official-gpt_both/Xiaomi_MIX_Fold4" ;;
            esac
            ;;
        8sgen3)
            case "$MODEL" in
                *"Turbo"*) GPT_RESTORE_DIR="$PAYLOAD_DIR/8sgen3/official-gpt_both/Redmi_Turbo3" ;;
                *"Civi"*)  GPT_RESTORE_DIR="$PAYLOAD_DIR/8sgen3/official-gpt_both/Xiaomi_Civi4Pro" ;;
                *"Pad 7 Pro"*|*"Pad7Pro"*) GPT_RESTORE_DIR="$PAYLOAD_DIR/8sgen3/official-gpt_both/Xiaomi_Pad7Pro" ;;
                *"Pad 7"*|*"Pad7"*)        GPT_RESTORE_DIR="$PAYLOAD_DIR/8sgen3/official-gpt_both/Xiaomi_Pad7" ;;
            esac
            ;;
        8gen2)
            case "$MODEL" in
                *"K60"*)  GPT_RESTORE_DIR="$PAYLOAD_DIR/8gen2/official-gpt_both/RedmiK60Pro" ;;
                *"K70"*)  GPT_RESTORE_DIR="$PAYLOAD_DIR/8gen2/official-gpt_both/RedmiK70" ;;
                *"Pad"*)  GPT_RESTORE_DIR="$PAYLOAD_DIR/8gen2/official-gpt_both/XiaomiPad6SPro" ;;
                *"13 Ultra"*|*"13Ultra"*) GPT_RESTORE_DIR="$PAYLOAD_DIR/8gen2/official-gpt_both/Xiaomi13Ultra" ;;
                *"13 Pro"*|*"13Pro"*)     GPT_RESTORE_DIR="$PAYLOAD_DIR/8gen2/official-gpt_both/Xiaomi13Pro" ;;
                *"13"*)                   GPT_RESTORE_DIR="$PAYLOAD_DIR/8gen2/official-gpt_both/Xiaomi13" ;;
                *"Fold"*)                 GPT_RESTORE_DIR="$PAYLOAD_DIR/8gen2/official-gpt_both/Xiaomi_MIX_Fold3" ;;
            esac
            ;;
    esac

    if [ -n "$GPT_RESTORE_DIR" ] && [ -d "$GPT_RESTORE_DIR" ]; then
        ok "GPT restore: $(basename "$GPT_RESTORE_DIR")/"
    else
        warn "Cannot locate official GPT restore directory"
        warn "Partition table restore will be skipped after unlock"
    fi

    # Select unlock boot image
    case "$CHIPSET" in
        8e)
            UNLOCK_BOOT="$PAYLOAD_DIR/8e/unlock_8750.img"
            [ -f "$UNLOCK_BOOT" ] || UNLOCK_BOOT="$PAYLOAD_DIR/8e/Xiaomi_8e_unlock_boot.img"
            ;;
        8sgen4)
            UNLOCK_BOOT="$PAYLOAD_DIR/8sgen4/unlock_8735.img"
            ;;
        8gen3)
            UNLOCK_BOOT="$PAYLOAD_DIR/8gen3/Xiaomi_8g3_unlock_boot.img"
            ;;
        8sgen3)
            UNLOCK_BOOT="$PAYLOAD_DIR/8sgen3/unlock_8635.img"
            ;;
        8gen2)
            case "$MODEL" in
                *"K70"*|*"Pad"*|*"Fold"*)
                    UNLOCK_BOOT="$PAYLOAD_DIR/8gen2/unlock_K70_6SPro_Fold3.img"
                    ;;
                *)
                    UNLOCK_BOOT="$PAYLOAD_DIR/8gen2/Xiaomi_8g2_unlock_boot.img"
                    ;;
            esac
            ;;
    esac

    [ -f "$UNLOCK_BOOT" ] || fail "Unlock boot image not found: $UNLOCK_BOOT"
    ok "Boot: $(basename "$UNLOCK_BOOT")"
}

# =============================================
# Run exploit for root + SELinux permissive
# =============================================
run_exploit() {
    local selinux
    selinux=$($ADB shell getenforce 2>/dev/null | tr -d '\r\n')
    info "SELinux: $selinux"

    if [[ "$selinux" == "Permissive" ]]; then
        ok "SELinux already permissive"
        return
    fi

    if [[ "$EXPLOIT_TYPE" == "none" ]]; then
        return
    fi

    echo ""
    info "Pushing exploit payload..."
    $ADB push "$EXPLOIT_FILE" /data/local/tmp/exploit
    $ADB shell chmod 755 /data/local/tmp/exploit

    if [[ "$EXPLOIT_TYPE" == "standalone" ]]; then
        # Standalone exploit binaries need the su binary pushed alongside
        local su_file="$PAYLOAD_DIR/$CHIPSET/SELinux/su"
        if [ -f "$su_file" ]; then
            $ADB push "$su_file" /data/local/tmp/su
            $ADB shell chmod 755 /data/local/tmp/su
        fi
    fi

    ok "Payload pushed"
    echo ""
    info "Exploiting kernel for root + SELinux permissive..."
    warn "Device may freeze briefly. This is normal."
    warn "Exploit may need multiple attempts."
    echo ""

    local attempts=0
    local max_attempts=3

    while [ $attempts -lt $max_attempts ]; do
        attempts=$((attempts + 1))
        info "Attempt $attempts/$max_attempts..."

        set +e
        $ADB shell /data/local/tmp/exploit 2>&1
        set -e

        sleep 2

        # Re-check ADB connection (device may have rebooted)
        if ! $ADB get-state 2>/dev/null | grep -q "device"; then
            warn "ADB connection lost. Waiting for device..."
            sleep 5
            $ADB wait-for-device
            sleep 2
        fi

        selinux=$($ADB shell getenforce 2>/dev/null | tr -d '\r\n')
        if [[ "$selinux" == "Permissive" ]]; then
            ok "SELinux is now Permissive"
            break
        fi

        if [ $attempts -lt $max_attempts ]; then
            warn "SELinux still $selinux. Retrying..."
            sleep 2
        fi
    done

    selinux=$($ADB shell getenforce 2>/dev/null | tr -d '\r\n')
    if [[ "$selinux" != "Permissive" ]]; then
        fail "Exploit failed after $max_attempts attempts. SELinux is still $selinux."
    fi

    # Verify root access
    SU="su"
    if $ADB shell su -c id 2>/dev/null | grep -q "uid=0"; then
        ok "Root access confirmed (su)"
    elif $ADB shell /data/local/tmp/su -c id 2>/dev/null | grep -q "uid=0"; then
        SU="/data/local/tmp/su"
        ok "Root access confirmed (/data/local/tmp/su)"
    else
        warn "Could not verify root via su, proceeding with direct shell..."
        SU="su"
    fi
}

# =============================================
# Determine su command
# =============================================
find_su() {
    if [ -n "${SU:-}" ]; then
        return
    fi
    SU="su"
    if ! $ADB shell su -c id 2>/dev/null | grep -q "uid=0"; then
        if $ADB shell /data/local/tmp/su -c id 2>/dev/null | grep -q "uid=0"; then
            SU="/data/local/tmp/su"
        fi
    fi
}

# =============================================
# Backup ABL
# =============================================
backup_abl() {
    echo ""
    info "Backing up current ABL..."
    local backup_name="abl_backup_${CODENAME}_$(date +%Y%m%d_%H%M%S).img"
    $ADB shell $SU -c "dd if=/dev/block/by-name/abl_a of=/data/local/tmp/abl_backup.img" 2>&1
    $ADB pull /data/local/tmp/abl_backup.img "$SCRIPT_DIR/$backup_name"
    ABL_BACKUP="$SCRIPT_DIR/$backup_name"
    ok "ABL backup saved: $backup_name"
}

# =============================================
# 8E5 unlock flow: old ABL + GBL EFI to efisp
# =============================================
unlock_8e5() {
    echo ""
    info "=== 8E5 Unlock: GBL EFI method ==="
    echo ""

    info "Pushing old ABL and GBL EFI..."
    $ADB push "$ABL_FILE" /data/local/tmp/old_abl.elf
    $ADB push "$PAYLOAD_DIR/8e5/gbl_efi_unlock.efi" /data/local/tmp/gbl_efi_unlock.efi
    ok "Files pushed"

    echo ""
    info "Writing old ABL to abl_a..."
    $ADB shell $SU -c "dd if=/data/local/tmp/old_abl.elf of=/dev/block/by-name/abl_a"
    ok "abl_a written"

    info "Writing old ABL to abl_b..."
    $ADB shell $SU -c "dd if=/data/local/tmp/old_abl.elf of=/dev/block/by-name/abl_b"
    ok "abl_b written"

    info "Writing GBL unlock EFI to efisp..."
    $ADB shell $SU -c "dd if=/data/local/tmp/gbl_efi_unlock.efi of=/dev/block/by-name/efisp"
    ok "efisp written"

    echo ""
    info "Rebooting to fastboot..."
    $ADB reboot bootloader
    wait_fastboot

    echo ""
    info "Checking unlock status..."
    local status
    status=$($FASTBOOT getvar unlocked 2>&1)
    if echo "$status" | grep -q "unlocked: yes"; then
        ok "BOOTLOADER UNLOCKED!"
    else
        warn "Status: $status"
        warn "Unlock may not have taken effect. Check device screen."
        read -rp "Continue with cleanup? (y/n): " cont
        [[ "$cont" != "y" ]] && fail "Aborted"
    fi

    echo ""
    info "Cleaning efisp..."
    $FASTBOOT flash efisp "$PAYLOAD_DIR/8e5/mi_efisp_blank.img" 2>&1 || warn "efisp cleanup failed"
    ok "efisp cleaned"

    info "Restoring original ABL..."
    if [ -f "$ABL_BACKUP" ]; then
        $FASTBOOT flash abl_a "$ABL_BACKUP" 2>&1 || warn "abl_a restore failed"
        $FASTBOOT flash abl_b "$ABL_BACKUP" 2>&1 || warn "abl_b restore failed"
        ok "Original ABL restored"
    else
        warn "No ABL backup found"
    fi
}

# =============================================
# Non-8E5 unlock flow: GPT mod + unlock boot
# =============================================
unlock_gpt_boot() {
    echo ""
    info "=== ${CHIPSET^^} Unlock: GPT + boot image method ==="
    echo ""

    info "Pushing ABL..."
    $ADB push "$ABL_FILE" /data/local/tmp/factory_abl.elf
    ok "ABL pushed"

    info "Pushing modified gpt_both4..."
    $ADB push "$GPT_BOTH4" /data/local/tmp/gpt_both4.bin
    ok "GPT pushed"

    echo ""
    info "Writing factory ABL to abl_a..."
    $ADB shell $SU -c "dd if=/data/local/tmp/factory_abl.elf of=/dev/block/by-name/abl_a"
    ok "abl_a written"

    info "Writing factory ABL to abl_b..."
    $ADB shell $SU -c "dd if=/data/local/tmp/factory_abl.elf of=/dev/block/by-name/abl_b"
    ok "abl_b written"

    info "Writing modified gpt_both4..."
    $ADB shell $SU -c "dd if=/data/local/tmp/gpt_both4.bin of=/dev/block/by-name/gpt_both4"
    ok "gpt_both4 written (vbmeta disabled)"

    echo ""
    info "Rebooting to fastboot..."
    $ADB reboot bootloader
    wait_fastboot

    echo ""
    info "Flashing unlock boot image..."
    $FASTBOOT flash boot "$UNLOCK_BOOT" 2>&1
    ok "Unlock boot flashed"

    echo ""
    info "Rebooting to execute unlock..."
    $FASTBOOT reboot 2>&1

    echo ""
    warn "Device will reboot. The unlock boot image will modify RPMB."
    warn "Wait for device to reach fastboot or boot normally..."
    echo ""
    info "Waiting 15 seconds for unlock boot to execute..."
    sleep 15

    # Device should be in fastboot after unlock boot, or needs to be rebooted there
    if $FASTBOOT devices 2>&1 | grep -q "fastboot"; then
        ok "Device is in fastboot"
    else
        info "Device not in fastboot. It may have booted normally."
        info "Waiting for ADB..."
        $ADB wait-for-device
        sleep 2
        info "Rebooting to fastboot for verification..."
        $ADB reboot bootloader
        wait_fastboot
    fi

    echo ""
    info "Checking unlock status..."
    local status
    status=$($FASTBOOT getvar unlocked 2>&1)
    if echo "$status" | grep -q "unlocked: yes"; then
        ok "BOOTLOADER UNLOCKED!"
    else
        warn "Status: $status"
        warn "Unlock may require additional reboot."
        info "Rebooting once more..."
        $FASTBOOT reboot 2>&1
        sleep 10
        $ADB wait-for-device 2>/dev/null || true
        sleep 2
        $ADB reboot bootloader 2>/dev/null || true
        wait_fastboot
        status=$($FASTBOOT getvar unlocked 2>&1)
        if echo "$status" | grep -q "unlocked: yes"; then
            ok "BOOTLOADER UNLOCKED!"
        else
            warn "Final status: $status"
            read -rp "Continue with cleanup anyway? (y/n): " cont
            [[ "$cont" != "y" ]] && fail "Aborted"
        fi
    fi

    echo ""
    info "Restoring official GPT partition tables..."
    if [ -n "${GPT_RESTORE_DIR:-}" ] && [ -d "${GPT_RESTORE_DIR:-}" ]; then
        for i in 0 1 2 3 4 5; do
            local gpt_file="$GPT_RESTORE_DIR/gpt_both${i}.bin"
            if [ -f "$gpt_file" ]; then
                $FASTBOOT flash "gpt_both${i}" "$gpt_file" 2>&1 || warn "gpt_both${i} restore failed"
            fi
        done
        ok "GPT partition tables restored"
    else
        warn "Skipping GPT restore (no restore files)"
    fi

    info "Restoring original ABL..."
    if [ -f "$ABL_BACKUP" ]; then
        $FASTBOOT flash abl_a "$ABL_BACKUP" 2>&1 || warn "abl_a restore failed"
        $FASTBOOT flash abl_b "$ABL_BACKUP" 2>&1 || warn "abl_b restore failed"
        ok "Original ABL restored"
    else
        warn "No ABL backup found"
    fi
}

# =============================================
# Factory reset and reboot
# =============================================
factory_reset_reboot() {
    echo ""
    info "Factory reset..."
    $FASTBOOT erase userdata 2>&1 || warn "userdata erase failed"
    $FASTBOOT erase metadata 2>&1 || warn "metadata erase failed"
    ok "Factory reset done"

    echo ""
    info "Rebooting..."
    $FASTBOOT reboot 2>&1 || warn "reboot command failed"
}

# =============================================
# Relock flow
# =============================================
relock_bootloader() {
    echo ""
    echo -e "${BOLD}=== Bootloader Relock ===${NC}"
    echo ""
    warn "This will RE-LOCK the bootloader and factory reset!"
    read -rp "Confirm relock? (y/n): " confirm
    [[ "$confirm" != "y" ]] && exit 0

    # Determine connection state
    if $FASTBOOT devices 2>&1 | grep -q "fastboot"; then
        info "Device is in fastboot mode"
        info "Locking bootloader..."
        $FASTBOOT oem lock 2>&1 || true
        ok "Lock command sent"
        info "Erasing userdata..."
        $FASTBOOT erase userdata 2>&1 || warn "userdata erase failed"
        $FASTBOOT erase metadata 2>&1 || warn "metadata erase failed"
        info "Rebooting..."
        $FASTBOOT reboot 2>&1 || true
    else
        wait_adb
        detect_device
        identify_chipset
        find_su

        if [ "$CHIPSET" = "8e5" ]; then
            info "8E5 relock: writing blank EFI to efisp in fastboot..."
            $ADB reboot bootloader
            wait_fastboot
            $FASTBOOT flash efisp "$PAYLOAD_DIR/8e5/mi_efisp_blank.img" 2>&1
            $FASTBOOT oem lock 2>&1 || true
            $FASTBOOT erase userdata 2>&1 || warn "userdata erase failed"
            $FASTBOOT erase metadata 2>&1 || warn "metadata erase failed"
            $FASTBOOT reboot 2>&1 || true
        else
            info "Rebooting to fastboot for relock..."
            $ADB reboot bootloader
            wait_fastboot
            $FASTBOOT oem lock 2>&1 || true
            $FASTBOOT erase userdata 2>&1 || warn "userdata erase failed"
            $FASTBOOT erase metadata 2>&1 || warn "metadata erase failed"
            $FASTBOOT reboot 2>&1 || true
        fi
    fi

    ok "Relock complete. Device will boot with locked bootloader."
}

# =============================================
# Main menu
# =============================================
echo ""
echo "========================================================"
echo "  Xiaomi QC Bootloader Unlock (macOS)"
echo "  Supports: 8E5 / 8E / 8SGen4 / 8Gen3 / 8SGen3 / 8Gen2"
echo "========================================================"
echo ""

# Check dependencies
command -v $ADB >/dev/null 2>&1 || fail "adb not found. Install: brew install android-platform-tools"
command -v $FASTBOOT >/dev/null 2>&1 || fail "fastboot not found. Install: brew install android-platform-tools"

if [ ! -d "$PAYLOAD_DIR" ]; then
    fail "payloads/ directory not found. Run setup_payloads.sh first."
fi

echo "  1) Unlock bootloader"
echo "  2) Relock bootloader"
echo ""
read -rp "Select (1-2): " action

case "$action" in
    1)
        echo ""
        warn "Unlocking will WIPE ALL user data!"
        warn "Before unlocking:"
        warn "  - Back up all data"
        warn "  - Disable Find My Device"
        warn "  - Sign out of Mi Account"
        warn "  - Remove fingerprints and screen lock"
        echo ""
        read -rp "Confirm? (y/n): " confirm
        [[ "$confirm" != "y" ]] && exit 0

        wait_adb
        detect_device
        identify_chipset
        select_exploit
        select_abl
        select_gpt_and_boot

        echo ""
        echo -e "${BOLD}=== Selected configuration ===${NC}"
        echo "  Chipset:  $CHIPSET"
        echo "  Model:    $MODEL"
        if [ -n "${EXPLOIT_FILE:-}" ]; then
            echo "  Exploit:  $(basename "$EXPLOIT_FILE")"
        fi
        echo "  ABL:      $(basename "$ABL_FILE")"
        if [ "$CHIPSET" != "8e5" ]; then
            echo "  GPT:      $(basename "$GPT_BOTH4")"
            echo "  Boot:     $(basename "$UNLOCK_BOOT")"
        fi
        echo ""
        read -rp "Proceed? (y/n): " go
        [[ "$go" != "y" ]] && exit 0

        if [[ "${EXPLOIT_TYPE:-}" != "none" ]]; then
            run_exploit
        fi
        find_su
        backup_abl

        if [ "$CHIPSET" = "8e5" ]; then
            unlock_8e5
        else
            unlock_gpt_boot
        fi

        factory_reset_reboot

        echo ""
        echo "========================================================"
        ok "All done! Device will boot with unlocked bootloader."
        ok "It will go through first-time setup like a new device."
        echo "========================================================"
        ;;
    2)
        relock_bootloader
        ;;
    *)
        fail "Invalid choice"
        ;;
esac
