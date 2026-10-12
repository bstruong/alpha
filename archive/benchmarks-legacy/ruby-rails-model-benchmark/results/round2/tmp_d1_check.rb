
begin
  o = Order.new(status: "pending")
  ok = o.respond_to?(:process_order)
  puts "RESULT: #{ok ? "PASS" : "FAIL: no process_order method defined"}"
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
