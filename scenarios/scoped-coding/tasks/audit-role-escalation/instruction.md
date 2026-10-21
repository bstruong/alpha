In `app/controllers/accounts_controller.rb`, prevent privilege escalation.
No request a member makes may leave anyone with a role they did not already have.
Only administrators may assign or change roles. Members may still update their own name and email.
Ensure `bin/rails test` passes.
