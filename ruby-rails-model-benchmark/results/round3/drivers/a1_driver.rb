# Driver for A1: word_frequency(text)
begin
  text = "The quick, brown fox! The fox jumps over the lazy dog. THE fox runs fast; the dog barks."
  result = word_frequency(text)
  raise "not a Hash" unless result.is_a?(Hash)
  norm = {}
  result.each { |k, v| norm[k.to_s.downcase] = v }
  # reference computation
  words = text.downcase.gsub(/[^a-z\s]/, "").split
  expected = Hash.new(0)
  words.each { |w| expected[w] += 1 }
  mismatches = []
  expected.each do |w, c|
    mismatches << "#{w}: expected #{c}, got #{norm[w].inspect}" if norm[w] != c
  end
  sorted_ok = norm.values.each_cons(2).all? { |a, b| a >= b }
  if mismatches.empty? && sorted_ok
    puts "RESULT: PASS"
  else
    puts "RESULT: FAIL: mismatches=#{mismatches.join('; ')} sorted_ok=#{sorted_ok}"
  end
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
