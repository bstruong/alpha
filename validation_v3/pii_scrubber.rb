# frozen_string_literal: true

# PiiScrubber — pure Ruby PII airgap scrubber.
# Detects and replaces Social Security Numbers and email addresses
# with redaction markers while leaving non-PII numeric strings intact.

# A pure-Ruby PII scrubber that redacts SSNs and email addresses.
class PiiScrubber
  SSN_PATTERN = /\b\d{3}-\d{2}-\d{4}\b/.freeze
  EMAIL_PATTERN = /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/.freeze

  def scrub(text)
    text.gsub(SSN_PATTERN, '[REDACTED_SSN]').gsub(EMAIL_PATTERN, '[REDACTED_EMAIL]')
  end
end
