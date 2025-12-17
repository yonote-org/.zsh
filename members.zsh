# Function to list members of a group
# Usage: members <group_name>
# Example: members admin
members() {
  dscl . -list /Users | while read user; do
    printf "$user "
    dsmemberutil checkmembership -U "$user" -G "$*"
  done | grep "is a member" | cut -d " " -f 1
}

