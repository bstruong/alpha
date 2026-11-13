PM ticket: config lines are `KEY=VALUE`. Ignore blanks and `#` comments. Trim keys/values. Later keys overwrite earlier ones.
Implement in `lib/line_parser.rb`. POST `/tools/parse_config` must show the parsed pairs. Leave tests green.
