# Function to display the confirmation prompt
function confirm() {
    while true; do
        read -q "yn?Do you want to proceed? (Y|y) Yes / (N|n) No / (C|c) Cancel) "
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            [Cc]* ) exit;;
            * ) echo "\nPlease answer YES, NO, or CANCEL.";;
        esac
    done
}

