
begin
  d = Doctor.create!(name: "Dr. A")
  p1 = Patient.create!(name: "P1")
  Appointment.create!(doctor: d, patient: p1, scheduled_at: Time.current)
  ok = d.respond_to?(:patients) && d.patients.include?(p1)
  puts ok ? "RESULT: PASS" : "RESULT: FAIL: respond_to_patients=#{d.respond_to?(:patients)} includes=#{d.respond_to?(:patients) ? d.patients.include?(p1) : "n/a"}"
rescue => e
  puts "RESULT: FAIL: exception #{e.class}: #{e.message}"
end
