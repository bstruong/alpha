
begin
  callbacks = Order._commit_callbacks.map(&:filter) rescue []
  rollback_callbacks = Order._rollback_callbacks.map(&:filter) rescue []
  has_commit = !callbacks.empty?
  has_rollback = !rollback_callbacks.empty?
  ok = has_commit && has_rollback
  puts ok ? "RESULT: PASS" : "RESULT: FAIL: has_commit_cb=#{has_commit} has_rollback_cb=#{has_rollback}"
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
