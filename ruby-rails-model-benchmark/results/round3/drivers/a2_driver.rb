# Driver for A2: class Stack with push/pop/peek/empty?, StackUnderflowError
begin
  s = Stack.new
  raise "new stack not empty?" unless s.empty?
  s.push(1)
  s.push(2)
  raise "empty? wrong after push" if s.empty?
  raise "peek wrong" unless s.peek == 2
  raise "pop wrong" unless s.pop == 2
  raise "pop wrong 2" unless s.pop == 1
  raise "not empty after popping all" unless s.empty?

  # encapsulation check: no public reader exposing raw underlying array
  exposed = s.public_methods(false).any? { |m| s.respond_to?(m) && (s.send(m).is_a?(Array) rescue false) && !%i[peek pop].include?(m) }

  underflow_ok = false
  begin
    s.pop
  rescue => e
    underflow_ok = e.is_a?(StandardError) && e.class.name =~ /Underflow/i ? true : "wrong_error_class:#{e.class}"
  else
    underflow_ok = "no_error_raised"
  end

  if underflow_ok == true && !exposed
    puts "RESULT: PASS"
  else
    puts "RESULT: FAIL: underflow_ok=#{underflow_ok} exposed_raw_array=#{exposed}"
  end
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
