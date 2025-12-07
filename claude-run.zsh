claude-run() {
  # Check if there's an active AWS session
  if ! aws sts get-caller-identity --profile=claude-code &>/dev/null; then
    # No active session or session expired, run AWS SSO login
    aws sso login --profile=claude-code
  fi
  
  # Then run claude with the required environment variables
    AWS_PROFILE=claude-code \
    ANTHROPIC_MODEL=global.anthropic.claude-sonnet-4-5-20250929-v1:0 \
    ANTHROPIC_SMALL_FAST_MODEL=global.anthropic.claude-3-5-haiku-20241022-v1:0 \
    CLAUDE_CODE_USE_BEDROCK=1 \
    AWS_REGION=eu-west-1 \
    claude --dangerously-skip-permissions
}

