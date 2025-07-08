#!/bin/bash

# Snap Manager with Gum TUI
# A comprehensive snap package management tool using Gum for the interface



# Check if gum is installed
if ! command -v gum &> /dev/null; then
    echo "Error: Gum is not installed. Please install it first:"
    echo "https://github.com/charmbracelet/gum"
    exit 1
fi

# Check if snap is installed
if ! command -v snap &> /dev/null; then
    echo "Error: Snap is not installed on this system."
    exit 1
fi

# Function to get list of installed snaps
get_installed_snaps() {
    snap list --unicode=never | tail -n +2 | awk '{print $1}'
}

# Function to get snap info
get_snap_info() {
    local snap_name="$1"
    snap info "$snap_name" 2>/dev/null
}

# Function to get snap services
get_snap_services() {
    local snap_name="$1"
    snap services "$snap_name" 2>/dev/null | tail -n +2 | awk '{print $1}'
}

# Function to get available channels with versions
get_snap_channels() {
    local snap_name="$1"
    snap info "$snap_name" | awk '
    BEGIN { in_channels = 0 }
    /^channels:/ { in_channels = 1; next }
    /^[^ ]/ && in_channels { in_channels = 0 }
    in_channels && /^\s+[a-zA-Z0-9\/]+:/ {
        # Extract channel name and full line
        match($0, /^\s+([a-zA-Z0-9\/]+):\s+(.*)$/, arr)
        channel = arr[1]
        rest = arr[2]
        
        if (rest == "^") {
            # Just show channel name for "same as above"
            printf "%s\n", channel
        } else if (rest != "") {
            # Extract version and revision from the rest
            # Format: version date (revision) size -
            if (match(rest, /^([^\s]+)\s+[0-9-]+\s+\(([0-9]+)\)/, version_arr)) {
                version = version_arr[1]
                revision = version_arr[2]
                printf "%s - %s (%s)\n", channel, version, revision
            } else if (match(rest, /^([^\s]+)/, version_arr)) {
                # Just version, no revision
                version = version_arr[1]
                printf "%s - %s\n", channel, version
            } else {
                # Fallback to just channel name
                printf "%s\n", channel
            }
        } else {
            # No version info
            printf "%s\n", channel
        }
    }
    '
}

# Function to extract channel name from formatted string
extract_channel_name() {
    local formatted_choice="$1"
    # Extract just the channel name (before the first " - ")
    echo "$formatted_choice" | sed 's/ - .*//'
}

# Function to show snap list and let user choose
choose_snap() {
    local title="$1"
    local snaps
    snaps=$(get_installed_snaps)
    
    if [ -z "$snaps" ]; then
        gum style --foreground="#E95420" "No snaps installed on this system."
        return 1
    fi
    
    local choice
    choice=$(gum choose --header="$title" "← Back" $snaps)
    
    if [ "$choice" = "← Back" ]; then
        return 1
    fi
    
    echo "$choice"
}

# Function to wait for user input (only when not going back)
wait_for_input() {
    echo
    gum style --foreground="#E95420" "Press any key to continue..."
    read -n 1
}

# Function to get all versions of a specific snap
get_snap_versions() {
    local snap_name="$1"
    snap list --all "$snap_name" --unicode=never | tail -n +2 | while IFS= read -r line; do
        # Extract revision, version, and notes
        local rev=$(echo "$line" | awk '{print $3}')
        local version=$(echo "$line" | awk '{print $2}')
        local notes=$(echo "$line" | awk '{print $NF}')
        
        # Create a formatted display string
        if [ "$notes" = "disabled" ]; then
            echo "$version (Rev: $rev) - disabled"
        else
            echo "$version (Rev: $rev) - current"
        fi
    done
}

# Function to extract revision number from formatted choice
extract_revision() {
    local formatted_choice="$1"
    # Extract revision number from string like "version (Rev: 12345) - status"
    echo "$formatted_choice" | sed 's/.*Rev: \([0-9]*\).*/\1/'
}

# Function to revert snap to specific version
revert_snap_to_version() {
    gum style --foreground="#E95420" "Revert Snap to Specific Version"
    
    local snap_name
    snap_name=$(choose_snap "Select snap to revert to specific version:")
    
    if [ -n "$snap_name" ]; then
        # Get all versions of the selected snap
        local versions
        versions=$(get_snap_versions "$snap_name")
        
        if [ -z "$versions" ]; then
            gum style --foreground="#E95420" "No versions found for $snap_name or snap not installed."
            wait_for_input
            return
        fi
        
        # Check if there are multiple versions available
        local version_count
        version_count=$(echo "$versions" | wc -l)
        
        if [ "$version_count" -eq 1 ]; then
            gum style --foreground="#E95420" "Only one version available for $snap_name. No other versions to revert to."
            wait_for_input
            return
        fi
        
        # Let user choose from available versions
        local version_choice
        version_choice=$(echo -e "← Back\n$versions" | gum choose --header="Select version to revert $snap_name to:")
        
        if [ "$version_choice" != "← Back" ] && [ -n "$version_choice" ]; then
            # Extract revision number from the choice
            local revision
            revision=$(extract_revision "$version_choice")
            
            # Extract version for display
            local version_display
            version_display=$(echo "$version_choice" | sed 's/ (Rev:.*//')
            
            if [ -n "$revision" ]; then
                gum confirm "Revert $snap_name to version $version_display (revision $revision)?" && {
                    # First authenticate with sudo
                    sudo -v
                    
                    # Then run the revert with spinner
                    gum spin --spinner="dot" --title="Reverting $snap_name to revision $revision..." -- \
                        sudo snap revert "$snap_name" --revision="$revision"
                    
                    if [ $? -eq 0 ]; then
                        gum style --foreground="#E95420" "✓ Successfully reverted $snap_name to version $version_display"
                    else
                        gum style --foreground="#E95420" "✗ Failed to revert $snap_name to version $version_display"
                    fi
                    wait_for_input
                }
            else
                gum style --foreground="#E95420" "✗ Could not extract revision number from selection"
                wait_for_input
            fi
        fi
    fi
}

# Function to revert snap
revert_snap() {
    gum style --foreground="#E95420" "Revert Snap Package"
    
    local snap_name
    snap_name=$(choose_snap "Select snap to revert:")
    
    if [ -n "$snap_name" ]; then
        gum confirm "Are you sure you want to revert $snap_name to its previous version?" && {
            # First authenticate with sudo
            sudo -v
            
            # Then run the revert with spinner
            gum spin --spinner="dot" --title="Reverting $snap_name..." -- \
                sudo snap revert "$snap_name"
            
            if [ $? -eq 0 ]; then
                gum style --foreground="#E95420" "✓ Successfully reverted $snap_name"
            else
                gum style --foreground="#E95420" "✗ Failed to revert $snap_name"
            fi
            wait_for_input
        }
    fi
}

# Function to switch channels
switch_channels() {
    gum style --foreground="#E95420" "Switch Snap Channel"
    
    local snap_name
    snap_name=$(choose_snap "Select snap to switch channel:")
    
    if [ -n "$snap_name" ]; then
        # Get available channels with versions
        local channels_with_versions
        channels_with_versions=$(get_snap_channels "$snap_name")
        
        if [ -n "$channels_with_versions" ]; then
            local channel_choice
            channel_choice=$(echo -e "← Back\n$channels_with_versions" | gum choose --header="Select channel for $snap_name:")
            
            if [ "$channel_choice" != "← Back" ] && [ -n "$channel_choice" ]; then
                local channel_name
                channel_name=$(extract_channel_name "$channel_choice")
                
                gum confirm "Switch $snap_name to channel $channel_name?" && {
                    # First authenticate with sudo
                    sudo -v
                    
                    # Then run the channel switch with spinner
                    gum spin --spinner="dot" --title="Switching $snap_name to $channel_name..." -- \
                        sudo snap refresh "$snap_name" --channel="$channel_name"
                    
                    if [ $? -eq 0 ]; then
                        gum style --foreground="#E95420" "✓ Successfully switched $snap_name to $channel_name"
                    else
                        gum style --foreground="#E95420" "✗ Failed to switch $snap_name to $channel_name"
                    fi
                    wait_for_input
                }
            fi
        else
            gum style --foreground="#E95420" "No channels available for $snap_name"
            wait_for_input
        fi
    fi
}

# Function to get running snap changes
get_running_changes() {
    snap changes | tail -n +2 | awk '$2 != "Done" && $2 != "Error" && $1 != "" && $1 != "-" {
        # Extract ID, Status, and Summary (last field)
        id = $1
        status = $2
        # Find the summary which starts after the last date/time field
        summary_start = 0
        for (i = 3; i <= NF; i++) {
            if ($i == "-" || match($i, /^[0-9]{4}-[0-9]{2}-[0-9]{2}/) || match($i, /^(today|yesterday)/)) {
                summary_start = i + 1
            }
        }
        if (summary_start > 0 && summary_start <= NF) {
            summary = ""
            for (i = summary_start; i <= NF; i++) {
                summary = summary $i " "
            }
            print id " - " status " - " summary
        } else {
            print id " - " status " - (no summary)"
        }
    }'
}

# Function to kill running snap process
kill_running_process() {
    gum style --foreground="#E95420" "Kill Running Snap Process"
    
    local running_changes
    running_changes=$(get_running_changes)
    
    if [ -z "$running_changes" ]; then
        gum style --foreground="#E95420" "No running snap processes found."
        wait_for_input
        return
    fi
    
    local choice
    choice=$(echo -e "← Back\n$running_changes" | gum choose --header="Select process to kill:")
    
    if [ "$choice" = "← Back" ] || [ -z "$choice" ]; then
        return
    fi
    
    # Extract the ID from the choice (first part before first " - ")
    local process_id
    process_id=$(echo "$choice" | cut -d' ' -f1)
    
    gum confirm "Are you sure you want to abort process $process_id?" && {
        # First authenticate with sudo
        sudo -v
        
        # Then run the abort with spinner
        gum spin --spinner="dot" --title="Aborting process $process_id..." -- \
            sudo snap abort "$process_id"
        
        if [ $? -eq 0 ]; then
            gum style --foreground="#E95420" "✓ Successfully aborted process $process_id"
        else
            gum style --foreground="#E95420" "✗ Failed to abort process $process_id"
        fi
        wait_for_input
    }
}

add_permissions() {
    gum style --foreground="#E95420" "Manage Snap Permissions"

    local snap_name
    snap_name=$(choose_snap "Select snap to manage permissions:")

    if [ -z "$snap_name" ]; then
        return
    fi

    # Build mapping: user-facing label → plug
    local options_map=""
    local line
    while IFS= read -r line; do
        local plug slot
        plug=$(echo "$line" | awk '{print $2}')
        slot=$(echo "$line" | awk '{print $3}')

        if [ "$slot" = "-" ]; then
            local label="$plug"
            options_map+="$label|$plug"$'\n'
        fi
    done < <(snap connections "$snap_name" | tail -n +2)

    if [ -z "$options_map" ]; then
        gum style --foreground="#E95420" "All permissions are already connected for $snap_name"
        wait_for_input
        return
    fi

    # Display user-friendly list
    local labels
    labels=$(echo "$options_map" | cut -d'|' -f1)

    local selected
    selected=$(echo "$labels" | gum filter --no-limit --header="Select permissions to connect:")

    if [ -z "$selected" ]; then
        gum style --foreground="#E95420" "No permissions selected."
        wait_for_input
        return
    fi

    sudo -v  # Authenticate once

    # Run snap connect for each selected plug
    while IFS= read -r label; do
        local plug
        plug=$(echo "$options_map" | grep "^$label|" | cut -d'|' -f2)
        gum spin --spinner="dot" --title="Connecting $plug..." -- \
            sudo snap connect "$plug"
    done <<< "$selected"

    gum style --foreground="#E95420" "✓ Selected permissions connected."
    wait_for_input
}

revoke_permissions() {
    gum style --foreground="#E95420" "Revoke Snap Permissions"

    local snap_name
    snap_name=$(choose_snap "Select snap to revoke permissions:")

    if [ -z "$snap_name" ]; then
        return
    fi

    # Build list of manual connections
    local options_map=""
    local line
    while IFS= read -r line; do
        local plug note
        plug=$(echo "$line" | awk '{print $2}')
        note=$(echo "$line" | awk '{print $4}')

        if [ "$note" = "manual" ]; then
            local label="$plug"
            options_map+="$label|$plug"$'\n'
        fi
    done < <(snap connections "$snap_name" | tail -n +2)

    if [ -z "$options_map" ]; then
        gum style --foreground="#E95420" "No manually connected permissions found for $snap_name"
        wait_for_input
        return
    fi

    # Display options
    local labels
    labels=$(echo "$options_map" | cut -d'|' -f1)

    local selected
    selected=$(echo "$labels" | gum filter --no-limit --header="Select permissions to revoke:")

    if [ -z "$selected" ]; then
        gum style --foreground="#E95420" "No permissions selected."
        wait_for_input
        return
    fi

    sudo -v  # Authenticate once

    while IFS= read -r label; do
        local plug
        plug=$(echo "$options_map" | grep "^$label|" | cut -d'|' -f2)
        gum spin --spinner="dot" --title="Disconnecting $plug..." -- \
            sudo snap disconnect "$plug"
    done <<< "$selected"

    gum style --foreground="#E95420" "✓ Selected permissions revoked."
    wait_for_input
}

# Function to view snap configuration
view_configuration() {
    while true; do
        clear
        gum style --foreground="#E95420" "View Snap Configuration"
        
        local snap_name
        snap_name=$(choose_snap "Select snap to view configuration:")
        
        if [ -n "$snap_name" ]; then
            # Get snap info
            snap info "$snap_name" | gum pager
            
            # Check if snap has configuration options
            local config_options
            config_options=$(snap get "$snap_name" 2>/dev/null)
            
            if [ -n "$config_options" ]; then
                gum style --foreground="#E95420" "Configuration Options for $snap_name:"
                echo "$config_options" | gum pager
            fi
        else
            # User chose "← Back", exit the loop
            break
        fi
    done
}

manage_permissions_menu() {
    while true; do
        clear
        gum style --foreground="#E95420" "Manage Permissions"

        local choice
        choice=$(gum choose --header="Permission options:" \
            "← Back" \
            "Connect missing permissions" \
            "Revoke manual permissions")

        case "$choice" in
            "← Back")
                break
                ;;
            "Connect missing permissions")
                add_permissions
                ;;
            "Revoke manual permissions")
                revoke_permissions
                ;;
        esac
    done
}

manage_offline_snaps() {
    while true; do
        clear
        gum style --foreground="#E95420" "Manage Offline Snaps"
        
        local choice
        choice=$(gum choose --header="Offline snap options:" \
            "← Back" \
            "Download snaps for offline use" \
            "Install offline snaps")
        
        case "$choice" in
            "← Back")
                break
                ;;
            "Download snaps for offline use")
                gum style --foreground="#E95420" "Download Installed Snaps for Offline Use"

                local snaps
                snaps=$(get_installed_snaps)

                if [ -z "$snaps" ]; then
                    gum style --foreground="#E95420" "No snaps are currently installed."
                    wait_for_input
                    continue
                fi

                local selected
                selected=$(echo "$snaps" | gum filter --no-limit --header="Select snaps to download for offline use:")

                if [ -z "$selected" ]; then
                    gum style --foreground="#E95420" "No snaps selected."
                    wait_for_input
                    continue
                fi

                # Target directory
                local target_dir="$HOME/Downloaded_Snaps"
                mkdir -p "$target_dir"

                sudo -v  # Authenticate once

                echo "$selected" | while read -r snap; do
                    gum spin --spinner="dot" --title="Downloading $snap to $target_dir..." -- \
                        snap download "$snap" --target-directory="$target_dir"
                done

                gum style --foreground="#E95420" "✓ All selected snaps downloaded to $target_dir"
                wait_for_input
                ;;
            "Install offline snaps")
                gum style --foreground="#E95420" "Install Downloaded Snaps"

                local target_dir="$HOME/Downloaded_Snaps"
                if [ ! -d "$target_dir" ]; then
                    gum style --foreground="#E95420" "No downloaded snaps found in $target_dir."
                    wait_for_input
                    continue
                fi

                # List all .snap files in the directory (without path)
                local snap_files
                snap_files=$(ls "$target_dir"/*.snap 2>/dev/null | xargs -n1 basename)
                
                if [ -z "$snap_files" ]; then
                    gum style --foreground="#E95420" "No .snap files found in $target_dir."
                    wait_for_input
                    continue
                fi

                local selected
                selected=$(echo "$snap_files" | gum filter --no-limit --header="Select snaps to install:")

                if [ -z "$selected" ]; then
                    gum style --foreground="#E95420" "No snaps selected."
                    wait_for_input
                    continue
                fi

                sudo -v  # Authenticate once

                echo "$selected" | while read -r snap_file; do
                    local snap_name="${snap_file%.snap}"          # Remove .snap extension
                    local assert_file="$target_dir/${snap_name}.assert"

                    if [ ! -f "$assert_file" ]; then
                        gum style --foreground="#E95420" "Warning: No assertion file found for $snap_name, skipping ack."
                    else
                        gum spin --spinner="dot" --title="Acknowledging $assert_file..." -- \
                            sudo snap ack "$assert_file"
                    fi

                    gum spin --spinner="dot" --title="Installing $snap_file..." -- \
                        sudo snap install "$target_dir/$snap_file"

                done

                gum style --foreground="#E95420" "✓ All selected snaps installed from $target_dir"
                wait_for_input
                ;;
        esac
    done
}

# Function to stop auto updates
stop_auto_updates() {
    while true; do
        clear
        gum style --foreground="#E95420" "Manage Auto Updates"
        
        local choice
        choice=$(gum choose --header="Auto-update options:" \
            "← Back" \
            "Hold all snaps" \
            "Hold specific snap" \
            "Unhold all snaps" \
            "Unhold specific snap" \
            "Manage metered connection updates" \
            "Set revision retention limit")
        
        case "$choice" in
            "← Back")
                break
                ;;
            "Hold all snaps")
                gum confirm "Hold updates for all snaps?" && {
                    # First authenticate with sudo
                    sudo -v
                    
                    local snaps
                    snaps=$(get_installed_snaps)
                    for snap in $snaps; do
                        sudo snap refresh --hold "$snap"
                    done
                    gum style --foreground="#E95420" "✓ All snaps are now held from updates"
                    wait_for_input
                }
                ;;
            "Hold specific snap")
                local snap_name
                snap_name=$(choose_snap "Select snap to hold:")
                
                if [ -n "$snap_name" ]; then
                    # First authenticate with sudo
                    sudo -v
                    
                    # Then run the hold with spinner
                    gum spin --spinner="dot" --title="Holding $snap_name..." -- \
                        sudo snap refresh --hold "$snap_name"
                    
                    if [ $? -eq 0 ]; then
                        gum style --foreground="#E95420" "✓ Successfully held $snap_name"
                    else
                        gum style --foreground="#E95420" "✗ Failed to hold $snap_name"
                    fi
                    wait_for_input
                fi
                ;;
            "Unhold all snaps")
                gum confirm "Unhold updates for all snaps?" && {
                    # First authenticate with sudo
                    sudo -v
                    
                    local snaps
                    snaps=$(get_installed_snaps)
                    for snap in $snaps; do
                        sudo snap refresh --unhold "$snap"
                    done
                    gum style --foreground="#E95420" "✓ All snaps are now unheld from updates"
                    wait_for_input
                }
                ;;
            "Unhold specific snap")
                local snap_name
                snap_name=$(choose_snap "Select snap to unhold:")
                
                if [ -n "$snap_name" ]; then
                    # First authenticate with sudo
                    sudo -v
                    
                    # Then run the unhold with spinner
                    gum spin --spinner="dot" --title="Unholding $snap_name..." -- \
                        sudo snap refresh --unhold "$snap_name"
                    
                    if [ $? -eq 0 ]; then
                        gum style --foreground="#E95420" "✓ Successfully unheld $snap_name"
                    else
                        gum style --foreground="#E95420" "✗ Failed to unhold $snap_name"
                    fi
                    wait_for_input
                fi
                ;;
            "Manage metered connection updates")
                while true; do
                    clear
                    local metered_choice
                    metered_choice=$(gum choose --header="Metered connection options:" \
                        "← Back" \
                        "Hold updates on metered connections" \
                        "Allow updates on metered connections")
                    
                    case "$metered_choice" in
                        "← Back")
                            break
                            ;;
                        "Hold updates on metered connections")
                            gum confirm "Hold snap updates when on metered connections?" && {
                                sudo -v
                                gum spin --spinner="dot" --title="Setting metered connection hold..." -- \
                                    sudo snap set system refresh.metered=hold
                                
                                if [ $? -eq 0 ]; then
                                    gum style --foreground="#E95420" "✓ Snap updates will be held on metered connections"
                                else
                                    gum style --foreground="#E95420" "✗ Failed to set metered connection hold"
                                fi
                                wait_for_input
                            }
                            ;;
                        "Allow updates on metered connections")
                            gum confirm "Allow snap updates on metered connections?" && {
                                sudo -v
                                gum spin --spinner="dot" --title="Allowing metered connection updates..." -- \
                                    sudo snap set system refresh.metered=null
                                
                                if [ $? -eq 0 ]; then
                                    gum style --foreground="#E95420" "✓ Snap updates are now allowed on metered connections"
                                else
                                    gum style --foreground="#E95420" "✗ Failed to allow metered connection updates"
                                fi
                                wait_for_input
                            }
                            ;;
                    esac
                done
                ;;
            "Set revision retention limit")
                # Get current retention value
                current_retain=$(sudo snap get system refresh.retain)
                
                gum style --foreground="#E95420" "Current revision retention: $current_retain"
                echo
                
                local retain_value
                retain_value=$(gum input --placeholder="Enter number of revisions to retain (2-20)" --header="Set maximum number of snap revisions to retain:")
                
                if [ -n "$retain_value" ]; then
                    # Validate input
                    if [[ "$retain_value" =~ ^[0-9]+$ ]] && [ "$retain_value" -ge 2 ] && [ "$retain_value" -le 20 ]; then
                        gum confirm "Set revision retention limit to $retain_value?" && {
                            sudo -v
                            gum spin --spinner="dot" --title="Setting revision retention limit..." -- \
                                sudo snap set system refresh.retain=$retain_value
                            
                            if [ $? -eq 0 ]; then
                                gum style --foreground="#E95420" "✓ Revision retention limit set to $retain_value"
                            else
                                gum style --foreground="#E95420" "✗ Failed to set revision retention limit"
                            fi
                            wait_for_input
                        }
                    else
                        gum style --foreground="#E95420" "✗ Invalid input. Please enter a number between 2 and 20."
                        wait_for_input
                    fi
                fi
                ;;
        esac
    done
}

# Main menu function
main_menu() {
    while true; do
        clear
        gum style --foreground="#E95420" "Snap Manager"
        
        local choice
        choice=$(gum choose --header="Select an option:" \
            "Revert snap" \
            "Revert snap to specific version" \
            "Kill running process" \
            "Manage auto updates" \
            "Switch channels" \
            "Manage offline snaps" \
            "View configuration" \
            "Manage permissions" \
            "Quit")
        
        case "$choice" in
            "Revert snap")
                revert_snap
                ;;
            "Revert snap to specific version")
                revert_snap_to_version
                ;;    
            "Kill running process")
                kill_running_process
                ;;    
            "Manage auto updates")
                stop_auto_updates
                ;;       
            "Switch channels")
                switch_channels
                ;;
            "Manage offline snaps")
                manage_offline_snaps
                ;;
            "View configuration")
                view_configuration
                ;;
            "Manage permissions")
                manage_permissions_menu
                ;;
            "Quit")
                gum style --foreground="#E95420" "Goodbye!"
                exit 0
                ;;
        esac
    done
}

# Start the application
main_menu