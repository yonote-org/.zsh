alias ls="ls -G"
alias ll="ls -lah"
alias finder="open /System/Library/CoreServices/Finder.app"
cdw() { cd ~/workspaces/"$1" }
_cdw() { _path_files -W ~/workspaces -/ }
(( $+functions[compdef] )) || { autoload -Uz compinit && compinit -u }
compdef _cdw cdw
alias cdr='cd_git_root'

