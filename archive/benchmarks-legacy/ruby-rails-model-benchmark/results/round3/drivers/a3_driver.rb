# Driver for A3: safe_divide(a, b)
begin
  r1 = safe_divide(10, 2)
  r2 = safe_divide(10, 0)
  r3 = safe_divide(10, "a")
  ok = (r1 == 5) && r2.nil? && r3.nil?
  if ok
    puts "RESULT: PASS"
  else
    puts "RESULT: FAIL: r1=#{r1.inspect} r2=#{r2.inspect} r3=#{r3.inspect}"
  end
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
