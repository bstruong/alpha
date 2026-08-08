def extract_emails(text)
  text.scan(/[\w\.-]+@[\w\.-]+\.\w+/).uniq.sort
end

# Driver for A4: extract_emails(text)
begin
  text = "Contact us at Support@Example.com or sales@example.co.uk. Not an email: foo@bar Invalid@@x.com. Also try dev.team+alerts@sub.example.io, twice: dev.team+alerts@sub.example.io."
  result = extract_emails(text)
  raise "not an Array" unless result.is_a?(Array)
  norm = result.map(&:downcase)
  expected_subset = ["support@example.com", "sales@example.co.uk", "dev.team+alerts@sub.example.io"]
  missing = expected_subset - norm
  unique_ok = norm.uniq.length == norm.length
  sorted_ok = norm == norm.sort
  if missing.empty? && unique_ok
    puts "RESULT: PASS#{sorted_ok ? '' : ' (note: not sorted)'}"
  else
    puts "RESULT: FAIL: missing=#{missing} unique_ok=#{unique_ok} got=#{norm.inspect}"
  end
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
