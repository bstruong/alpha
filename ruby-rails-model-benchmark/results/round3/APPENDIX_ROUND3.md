# Round 3 Raw Output Appendix — qwen3:8b Direct Benchmark

Generated Sat Aug  8 10:53:58 AM PDT 2026


---
## A1 (Category A)

**Prompt:** Write a Ruby method `word_frequency(text)` that returns a hash of word => count, case-insensitive, ignoring punctuation, sorted by count descending. Use Enumerable methods idiomatically. Provide just the method definition.


### qwen3:8b — run 1 | executes=True | behavior=PASS

```
```ruby
def word_frequency(text)
  text.downcase.gsub(/[^a-z\s]/, ' ').split.each_with_object(Hash.new(0)) do |word, hash|
    hash[word] += 1
  end.sort_by { |_, count| -count }.to_h
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=PASS

```
```ruby
def word_frequency(text)
  text.downcase.gsub(/[^a-z\s]/, ' ').split.each_with_object(Hash.new(0)) do |word, hash|
    hash[word] += 1
  end.sort_by { |_, count| -count }.to_h
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=PASS

```
```ruby
def word_frequency(text)
  text.downcase.gsub(/[^a-z\s]/, ' ').split
    .each_with_object(Hash.new(0)) { |word, hash| hash[word] += 1 }
    .sort_by { |_, count| -count }
    .to_h
end
```
```


---
## A2 (Category A)

**Prompt:** Write a Ruby class `Stack` with a properly encapsulated internal array (not exposed via attr_reader). Implement push, pop, peek, and empty? methods. Raise a custom error class `StackUnderflowError` when calling pop or peek on an empty stack.


### qwen3:8b — run 1 | executes=True | behavior=PASS

```
```ruby
class Stack
  class StackUnderflowError < StandardError; end

  def initialize
    @stack = []
  end

  def push(element)
    @stack << element
  end

  def pop
    raise StackUnderflowError, "Cannot pop from an empty stack" if empty?
    @stack.pop
  end

  def peek
    raise StackUnderflowError, "Cannot peek from an empty stack" if empty?
    @stack.last
  end

  def empty?
    @stack.empty?
  end
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=PASS

```
```ruby
class Stack
  class StackUnderflowError < StandardError; end

  def initialize
    @stack = []
  end

  def push(element)
    @stack << element
  end

  def pop
    raise StackUnderflowError, "Cannot pop from an empty stack" if empty?
    @stack.pop
  end

  def peek
    raise StackUnderflowError, "Cannot peek from an empty stack" if empty?
    @stack.last
  end

  def empty?
    @stack.empty?
  end
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=PASS

```
```ruby
class Stack
  class StackUnderflowError < StandardError; end

  def initialize
    @stack = []
  end

  def push(element)
    @stack << element
  end

  def pop
    raise StackUnderflowError, "Cannot pop from an empty stack" if empty?
    @stack.pop
  end

  def peek
    raise StackUnderflowError, "Cannot peek from an empty stack" if empty?
    @stack.last
  end

  def empty?
    @stack.empty?
  end
end
```
```


---
## A3 (Category A)

**Prompt:** Write a Ruby method `safe_divide(a, b)` that divides a by b, gracefully handling ZeroDivisionError and TypeError. On error, print a warning message and return nil. On success, return the quotient.


### qwen3:8b — run 1 | executes=True | behavior=PASS

```
```ruby
def safe_divide(a, b)
  begin
    a / b
  rescue ZeroDivisionError, TypeError
    puts "Warning: Division error occurred."
    nil
  end
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=PASS

```
```ruby
def safe_divide(a, b)
  begin
    a / b
  rescue ZeroDivisionError, TypeError => e
    puts "Warning: #{e.message}"
    nil
  end
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=PASS

```
```ruby
def safe_divide(a, b)
  begin
    a / b
  rescue ZeroDivisionError, TypeError => e
    puts "Warning: #{e.message}"
    nil
  end
end
```
```


---
## A4 (Category A)

**Prompt:** Write a Ruby method `extract_emails(text)` that uses a regular expression to extract all valid-looking email addresses from a block of text, returning them as a unique, sorted array.


### qwen3:8b — run 1 | executes=True | behavior=RESULT: FAIL: missing=["dev.team+alerts@sub.example.io"] unique_ok=true got=["support@example.com", "alerts@sub.example.io", "sales@example.co.uk"]

```
```ruby
def extract_emails(text)
  text.scan(/[\w\.-]+@[\w\.-]+\.\w+/).uniq.sort
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=RESULT: FAIL: missing=["sales@example.co.uk"] unique_ok=true got=["support@example.com", "dev.team+alerts@sub.example.io", "dev.team+alerts@sub.example.io.", "sales@example.co.uk."]

```
```ruby
def extract_emails(text)
  text.scan(/[\w\.\+-]+@[\w\.-]+\.[\w\.-]+/).sort.uniq
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=RESULT: FAIL: missing=["dev.team+alerts@sub.example.io"] unique_ok=true got=["support@example.com", "alerts@sub.example.io", "sales@example.co.uk"]

```
```ruby
def extract_emails(text)
  text.scan(/[\w\.-]+@[\w\.-]+\.\w+/).uniq.sort
end
```
```


---
## B1 (Category B)

**Prompt:** Write a Rails 7.1 migration that adds a `status` column (string, default "draft", not null) to an existing `articles` table, and adds a database index on that column.


### qwen3:8b — run 1 | executes=True | behavior=PASS

```
```ruby
# frozen_string_literal: true

class AddStatusToArticles < ActiveRecord::Migration[7.1]
  def change
    add_column :articles, :status, :string, default: "draft", null: false
    add_index :articles, :status
  end
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=PASS

```
```ruby
# == Schema Information
#
# Table name: articles
#
#  id         :integer          default(1), primary key
#  title      :string           not null
#  content    :text             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  status     :string           default("draft"), not null
#

class AddStatusToArticles < ActiveRecord::Migration[7.1]
  def change
    add_column :articles, :status, :string, default: "draft", null: false
    add_index :articles, :status
  end
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=PASS

```
```ruby
# == Schema Information
#
# Table name: articles
#
#  id         :integer          primary key
#  title      :string           not null
#  content    :text             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  status     :string           default("draft"), not null
#

class AddStatusToArticles < ActiveRecord::Migration[7.1]
  def change
    add_column :articles, :status, :string, default: "draft", null: false
    add_index :articles, :status
  end
end
```
```


---
## B2 (Category B)

**Prompt:** Write ActiveRecord validations for a Rails 7.1 `User` model: `email` must be present and unique (case-insensitive), `username` must be present with length between 3 and 20, and `age` must be numeric but may be nil.


### qwen3:8b — run 1 | executes=True | behavior=PASS

```
```ruby
class User < ApplicationRecord
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :username, presence: true, length: { in: 3..20 }
  validates :age, numericality: true, allow_nil: true
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=PASS

```
```ruby
class User < ApplicationRecord
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :username, presence: true, length: { in: 3..20 }
  validates :age, numericality: true, allow_nil: true
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=RESULT: FAIL: v1=true v2=false(errs=["Email can't be blank", "Username is too short (minimum is 3 characters)"]) v3=true(errs=[]) v4=true(errs=[])

```
```ruby
class User < ApplicationRecord
  validates :email, presence: true, uniqueness: { case_insensitive: true }
  validates :username, presence: true, length: { in: 3..20 }
  validates :age, numericality: true, allow_nil: true
end
```
```


---
## B3 (Category B)

**Prompt:** Write a Rails 7.1 controller action `PostsController#publish` (a member route) that transitions a post's status to "published" and sets `published_at` to the current time, then redirects back to the post with a flash notice on success, or a flash alert if the save fails.


### qwen3:8b — run 1 | executes=True | behavior=PASS

```
```ruby
# app/controllers/posts_controller.rb
class PostsController < ApplicationController
  def publish
    @post = Post.find(params[:id])
    @post.status = 'published'
    @post.published_at = Time.current

    if @post.save
      flash[:notice] = 'Post was successfully published.'
    else
      flash[:alert] = 'Failed to publish post.'
    end

    redirect_to @post
  end
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=PASS

```
```ruby
# app/controllers/posts_controller.rb
class PostsController < ApplicationController
  def publish
    @post = Post.find(params[:id])
    @post.status = 'published'
    @post.published_at = Time.current

    if @post.save
      flash[:notice] = 'Post was successfully published.'
    else
      flash[:alert] = 'Failed to publish post.'
    end

    redirect_to @post
  end
end
```
```


### qwen3:8b — run 3 | executes=False | behavior=RESULT: FAIL: status=published published_at=Sat, 08 Aug 2026 17:49:37.830533000 UTC +00:00 response=204 flash={"notice"=>"Post was successfully published."}

```
```ruby
# app/controllers/posts_controller.rb
class PostsController < ApplicationController
  def publish
    @post = Post.find(params[:id])
    @post.update!(
      status: 'published',
      published_at: Time.current
    )

    flash[:notice] = 'Post was successfully published.'
  rescue ActiveRecord::RecordInvalid => e
    flash[:alert] = 'Failed to publish post: #{e.message}'
  end
end
```
```


---
## B4 (Category B)

**Prompt:** Add an enum to a Rails 7.1 `Order` model for `status` with values pending, paid, shipped, cancelled, using the `validate: true` option introduced in Rails 7.1. Also add a scope `recent` that returns orders created in the last 7 days, ordered by created_at descending.


### qwen3:8b — run 1 | executes=True | behavior=RESULT: FAIL: exception ArgumentError: Enum values true must be either a non-empty hash or an array.

```
```ruby
# app/models/order.rb
class Order < ApplicationRecord
  enum status: { pending: 0, paid: 1, shipped: 2, cancelled: 3 }, validate: true

  scope :recent, -> { where(created_at: 7.days.ago..Time.current).order(created_at: :desc) }
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=RESULT: FAIL: exception ArgumentError: Enum values true must be either a non-empty hash or an array.

```
```ruby
# app/models/order.rb
class Order < ApplicationRecord
  enum status: { pending: 0, paid: 1, shipped: 2, cancelled: 3 }, validate: true

  scope :recent, -> { where(created_at: 7.days.ago..Time.current).order(created_at: :desc) }
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=RESULT: FAIL: exception ArgumentError: Enum values true must be either a non-empty hash or an array.

```
```ruby
# app/models/order.rb
class Order < ApplicationRecord
  enum status: { pending: 0, paid: 1, shipped: 2, cancelled: 3 }, validate: true

  scope :recent, -> { where(created_at: 7.days.ago..Time.current).order(created_at: :desc) }
end
```
```


---
## B5 (Category B)

**Prompt:** Write `config/routes.rb` entries for a resourceful `articles` route nested under an `admin` namespace, including a custom member route `publish` (POST) and a custom collection route `archived` (GET).


### qwen3:8b — run 1 | executes=True | behavior=PASS

```
```ruby
namespace :admin do
  resources :articles do
    member do
      post 'publish'
    end

    collection do
      get 'archived'
    end
  end
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=PASS

```
```ruby
namespace :admin do
  resources :articles do
    member do
      post 'publish'
    end

    collection do
      get 'archived'
    end
  end
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=PASS

```
```ruby
namespace :admin do
  resources :articles do
    member do
      post 'publish'
    end

    collection do
      get 'archived'
    end
  end
end
```
```


---
## C1 (Category C)

**Prompt:** Set up a background job in this Rails app to send a welcome email asynchronously when a user signs up.


### qwen3:8b — run 1

```
```ruby
# config/schedule.rb
every '0 5 * * *' do
  runner "User.send_welcome_emails"
end
```

```ruby
# app/jobs/user_job.rb
class UserJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find(user_id)
    UserMailer.welcome_email(user).deliver_later
  end
end
```

```ruby
# app/models/user.rb
class User < ApplicationRecord
  after_create :enqueue_welcome_job

  private

  def enqueue_welcome_job
    UserJob.perform_later(self.id)
  end
end
```

```ruby
# app/mailers/user_mailer.rb
class UserMailer < ApplicationMailer
  def welcome_email(user)
    @user = user
    mail to: @user.email, subject: 'Welcome to Our App!'
  end
end
```

```ruby
# config/application.rb
module YourApp
  class Application < Rails::Application
    config.active_job.queue_adapter = :sidekiq
  end
end
```

Make sure to install and configure Sidekiq for background job processing.
```


### qwen3:8b — run 2

```
```ruby
# config/routes.rb
Rails.application.routes.draw do
  root "users#new"
  post "/signup", to: "users#create"
end

# app/controllers/users_controller.rb
class UsersController < ApplicationController
  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      AsyncMailer.welcome_email(@user).deliver_later
      redirect_to root_path, notice: "Welcome!"
    else
      render :new
    end
  end

  private

  def user_params
    params.require(:user).permit(:email, :password)
  end
end

# app/jobs/async_mailer_job.rb
class AsyncMailerJob < ApplicationJob
  queue_as :default

  def perform(user)
    UserMailer.welcome_email(user).deliver_now
  end
end

# app/mailers/user_mailer.rb
class UserMailer < ApplicationMailer
  default from: "no-reply@example.com"

  def welcome_email(user)
    @user = user
    mail to: @user.email, subject: "Welcome to Our App!"
  end
end

# app/views/user_mailer/welcome_email.html.erb
<h1>Welcome, <%= @user.email %>!</h1>
<p>Thank you for signing up. We're excited to have you on board!</p>
```

Make sure to run `rails generate mailer UserMailer` if you haven't already.
```


### qwen3:8b — run 3

```
```ruby
# app/jobs/welcome_email_job.rb
class WelcomeEmailJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find(user_id)
    UserMailer.welcome_email(user).deliver_now
  end
end
```

```ruby
# app/models/user.rb
class User < ApplicationRecord
  after_create :enqueue_welcome_email

  private

  def enqueue_welcome_email
    WelcomeEmailJob.perform_later(self.id)
  end
end
```

```ruby
# config/routes.rb
Rails.application.routes.draw do
  resources :users, only: [:create]
end
```

```ruby
# config/sidekiq.yml
:concurrency: 5
:queues:
  - default
```

```bash
# Install Sidekiq and Redis
gem 'sidekiq'
gem 'redis'

# Then run:
bundle install
rails g sidekiq:worker
rails db:migrate
```

```bash
# Start Sidekiq
sidekiq
```
```


---
## C2 (Category C)

**Prompt:** Add user authentication to this Rails app.


### qwen3:8b — run 1

```
To add user authentication to your Rails app, you can use the `devise` gem. Here's how to do it step-by-step:

1. **Add Devise to Gemfile:**

```ruby
# Gemfile
gem 'devise'
```

2. **Install the Gem:**

```bash
bundle install
```

3. **Generate Devise Models:**

```bash
rails generate devise:install
rails generate devise User
rails db:migrate
```

4. **Update `config/routes.rb`:**

```ruby
# config/routes.rb
Rails.application.routes.draw do
  devise_for :users
  # Your other routes go here
end
```

5. **Update `app/models/user.rb`:**

```ruby
# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
end
```

6. **Add Authentication to Your Controllers (e.g., `app/controllers/application_controller.rb`):**

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :authenticate_user!
end
```

7. **Add Sign-In/Out Links to Your Layout (e.g., `app/views/layouts/application.html.erb`):**

```erb
<!-- app/views/layouts/application.html.erb -->
<!DOCTYPE html>
<html>
<head>
  <title>MyApp</title>
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>

  <%= stylesheet_link_tag 'application', media: 'all', 'data-turbo-track': 'reload' %>
  <%= javascript_pack_tag 'application', 'data-turbo-track': 'reload' %>
</head>

<body>
  <nav>
    <%= link_to 'Sign In', new_user_session_path if !current_user %>
    <%= link_to 'Sign Out', destroy_user_session_path if current_user %>
  </nav>

  <%= yield %>
</body>
</html>
```

Now your app has user authentication using Devise.
```


### qwen3:8b — run 2

```
To add user authentication to your Rails app, you can use the `devise` gem. Here's how to do it step-by-step:

1. Add `devise` to your Gemfile and run `bundle install`.
2. Generate the Devise model.
3. Run the migration.
4. Set up routes.
5. Set up the views.

Here's the complete code:

```ruby
# Gemfile
gem 'devise'
```

```bash
bundle install
rails generate devise:install
rails generate devise User
rails db:migrate
```

```ruby
# config/routes.rb
Rails.application.routes.draw do
  devise_for :users
  # Your other routes here
end
```

```ruby
# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
end
```

```erb
<!-- app/views/devise/registrations/edit.html.erb -->
<%= form_for(resource, as: resource, url: registration_path(resource_name), method: :put) do |f| %>
  <%= f.label :email %>
  <%= f.email_field :email, autofocus: true %>

  <%= f.label :password %>
  <%= f.password_field :password, autocomplete: "new-password" %>

  <%= f.label :password_confirmation %>
  <%= f.password_field :password_confirmation, autocomplete: "new-password" %>

  <%= f.submit "Update" %>
<% end %>
```

That's a basic setup. Customize views and add user roles as needed.
```


### qwen3:8b — run 3

```
To add user authentication to your Rails app, we'll use **Devise**, a popular authentication solution. Below is the complete setup:

```ruby
# Gemfile
gem 'devise'
```

```bash
# Run bundle install and generate Devise models
bundle install
rails generate devise:install
rails generate devise User
rails db:migrate
```

```ruby
# config/routes.rb
Rails.application.routes.draw do
  devise_for :users
  root to: "home#index"
end
```

```ruby
# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
end
```

```erb
<!-- app/views/home/index.html.erb -->
<% if user_signed_in? %>
  <p>Hello, <%= current_user.email %>!</p>
  <%= link_to 'Sign Out', destroy_user_session_path, method: :delete %>
<% else %>
  <%= link_to 'Sign In', new_user_session_path %>
  <%= link_to 'Sign Up', new_user_registration_path %>
<% end %>
```

This sets up user authentication with sign-in, sign-up, password recovery, and session management.
```


---
## C3 (Category C)

**Prompt:** Configure the asset pipeline for this Rails app to compile and serve a new stylesheet.


### qwen3:8b — run 1

```
To configure the asset pipeline in a Rails app to compile and serve a new stylesheet, follow these steps:

1. **Create the stylesheet file** in `app/assets/stylesheets/` (e.g., `custom.css.scss`).

2. **Add the stylesheet to the asset pipeline** by editing `app/assets/config/manifest.js`:

```js
// app/assets/config/manifest.js
//= link custom.css
```

3. **Ensure the stylesheet is included in the layout** by editing `app/views/layouts/application.html.erb`:

```erb
<!-- app/views/layouts/application.html.erb -->
<%= stylesheet_link_tag "application", media: "all" %>
```

4. **Restart the Rails server** if it's running, to ensure changes take effect.

5. **Precompile assets** for production (optional, if needed):

```bash
rails assets:precompile
```

This will make the stylesheet available in development and production environments.
```


### qwen3:8b — run 2

```
```ruby
# config/application.rb
module YourApp
  class Application < Rails::Application
    # Add new stylesheet to asset pipeline
    config.assets.paths << Rails.root.join('app', 'assets', 'stylesheets', 'custom')
  end
end
```

```erb
<!-- app/assets/stylesheets/application.css -->
/*
 *= require custom/custom_stylesheet
 */
```

```scss
/* app/assets/stylesheets/custom/custom_stylesheet.scss */
body {
  background-color: lightblue;
}
```
```


### qwen3:8b — run 3

```
To configure the asset pipeline in a Rails app to compile and serve a new stylesheet, follow these steps:

1. Place your stylesheet in the `app/assets/stylesheets` directory (e.g., `app/assets/stylesheets/custom.css.scss`).
2. Ensure the file is named with the `.css.scss` or `.css.erb` extension for SCSS or ERB support.
3. Add the stylesheet to the asset pipeline configuration.

```ruby
# config/application.rb
module YourApp
  class Application < Rails::Application
    # Precompile additional assets (application.js, application.css, and all non-JS/CSS files in app/assets/assets)
    config.assets.precompile += %w( custom.css.scss )
  end
end
```

4. Restart the Rails server if it's running, or use `rails assets:precompile` to precompile assets.

Now your new stylesheet will be compiled and served by the asset pipeline.
```


---
## D1 (Category D)

**Prompt:** Write a Rails model method `process_order` on an `Order` model that saves the order within a database transaction and enqueues an `OrderProcessorJob` to run afterward, ensuring the job cannot start running before the order is actually committed to the database.


### qwen3:8b — run 1 | executes=True | behavior=PASS | version=7.1-only (assumes immediate enqueue is safe)

```
```ruby
class Order < ApplicationRecord
  def process_order
    ApplicationRecord.transaction do
      save!
      OrderProcessorJob.perform_later(self.id)
    end
  rescue => e
    # Handle transaction rollback or errors
    raise e
  end
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=PASS | version=7.1-only (assumes immediate enqueue is safe)

```
```ruby
# app/models/order.rb
class Order < ApplicationRecord
  def process_order
    ActiveRecord::Base.transaction do
      save!
      OrderProcessorJob.perform_later(self.id)
    end
  end
end
```

```ruby
# app/jobs/order_processor_job.rb
class OrderProcessorJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    Order.find(order_id).process!
  end
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=PASS | version=7.1-only (assumes immediate enqueue is safe)

```
```ruby
# app/models/order.rb
class Order < ApplicationRecord
  def process_order
    ActiveRecord::Base.transaction do
      save!
      OrderProcessorJob.perform_later(self.id)
    end
  end
end
```
```


---
## D2 (Category D)

**Prompt:** Write a Rails config snippet or initializer you would add to a Rails app to enable YJIT for better performance in production.


### qwen3:8b — run 1 | executes=True | behavior=PASS | version=7.1-only (manual enable, no mention of 7.2 default)

```
```ruby
# config/environments/production.rb
Rails.application.configure do
  # Enable YJIT for improved performance in production
  config.enable_yjit = true
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=PASS | version=7.1-only (manual enable, no mention of 7.2 default)

```
```ruby
# config/environments/production.rb
Rails.application.configure do
  # Enable YJIT for better performance in production
  config.yjit.enabled = true

  # Other production settings...
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=PASS | version=7.1-only (manual enable, no mention of 7.2 default)

```
```ruby
# config/environments/production.rb
Rails.application.configure do
  # Enable YJIT for better performance in production
  config.yjit.enabled = true

  # Optimize for production
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?
  config.log_level = :debug
  config.log_tags = [ :request_id ]
  config.action_mailer.perform_caching = true
  config.active_support.deprecation = :log
  config.active_support.time_zone = 'UTC'
  config.active_support.utc_time_zone = 'UTC'
  config.i18n.fallbacks = true
  config.i18n.raise_on_missing_translations = true
  config.assets.compile = false
  config.assets.digest = true
  config.assets.version = '1.0'
end
```
```


---
## D3 (Category D)

**Prompt:** Write a Rails initializer that checks the running Ruby version at application boot and raises a clear error if it is below the minimum Ruby version required by this Rails app.


### qwen3:8b — run 1 | executes=True | behavior=RESULT: FAIL: exception loading initializer: NameError: uninitialized constant Rails | version=unknown

```
```ruby
# config/initializers/check_ruby_version.rb
unless RUBY_VERSION >= Rails.version.split('.').first.to_f
  raise "Ruby version is too low. This app requires Ruby #{Rails.version.split('.').first} or higher. Current Ruby version: #{RUBY_VERSION}"
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=RESULT: FAIL: exception loading initializer: NameError: uninitialized constant Rails | version=unknown

```
```ruby
# config/initializers/check_ruby_version.rb
unless RUBY_VERSION >= Rails::VERSION::STRING.split('.').first
  raise "Ruby version is too old. This app requires Ruby #{Rails::VERSION::STRING.split('.').first} or newer. Current Ruby version: #{RUBY_VERSION}"
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=RESULT: FAIL: exception loading initializer: NameError: uninitialized constant Rails | version=unknown

```
```ruby
# config/initializers/check_ruby_version.rb
require 'rubygems'

min_ruby_version = Gem::Version.new(Rails.version.split('.').first(2).join('.'))
current_ruby_version = Gem::Version.new(RUBY_VERSION)

if current_ruby_version < min_ruby_version
  raise "Ruby version is too low. Minimum required: #{min_ruby_version}, Current: #{current_ruby_version}"
end
```
```


---
## D4 (Category D)

**Prompt:** Write ActiveRecord model callbacks on an `Order` model: one that logs a message immediately after a database transaction successfully commits, and a separate one that logs a message when a transaction rolls back.


### qwen3:8b — run 1 | executes=True | behavior=PASS | version=n/a (after_commit/after_rollback predate 7.2)

```
```ruby
class Order < ApplicationRecord
  after_commit :log_commit_message, on: :update
  after_rollback :log_rollback_message, on: :update

  private

  def log_commit_message
    Rails.logger.info "Order #{id} successfully committed."
  end

  def log_rollback_message
    Rails.logger.info "Order #{id} rolled back."
  end
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=PASS | version=n/a (after_commit/after_rollback predate 7.2)

```
```ruby
class Order < ApplicationRecord
  after_commit :log_commit, on: :create
  after_rollback :log_rollback, on: :create

  private

  def log_commit
    Rails.logger.info "Order created successfully: #{id}"
  end

  def log_rollback
    Rails.logger.info "Order creation rolled back: #{id}"
  end
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=PASS | version=n/a (after_commit/after_rollback predate 7.2)

```
```ruby
class Order < ApplicationRecord
  after_commit :log_commit, on: :create
  after_rollback :log_rollback, on: :create

  private

  def log_commit
    Rails.logger.info "Order #{@id} was successfully committed."
  end

  def log_rollback
    Rails.logger.info "Order #{@id} was rolled back."
  end
end
```
```


---
## E1 (Category E)

**Prompt:** Add pagination to the `ArticlesController#index` action using the Kaminari gem, showing 10 articles per page.


### qwen3:8b — run 1 | executes=True | behavior=PASS

```
```ruby
# app/controllers/articles_controller.rb
class ArticlesController < ApplicationController
  def index
    @articles = Article.order(created_at: :desc).page(params[:page]).per(10)
  end
end
```

Make sure to add Kaminari to your Gemfile and run `bundle install`:

```ruby
# Gemfile
gem 'kaminari'
```

Then run:

```bash
bundle install
rails generate kaminari:install
```
```


### qwen3:8b — run 2 | executes=True | behavior=PASS

```
```ruby
# app/controllers/articles_controller.rb
class ArticlesController < ApplicationController
  def index
    @articles = Article.order('created_at DESC').page(params[:page]).per(10)
  end
end
```

```ruby
# config/routes.rb
Rails.application.routes.draw do
  resources :articles, only: [:index]
end
```

```erb
<!-- app/views/articles/index.html.erb -->
<%= paginate @articles %>

<% @articles.each do |article| %>
  <div>
    <h2><%= article.title %></h2>
    <p><%= article.body %></p>
  </div>
<% end %>
```

Make sure to add Kaminari to your Gemfile and run `bundle install`:

```ruby
# Gemfile
gem 'kaminari'
```
```


### qwen3:8b — run 3 | executes=True | behavior=PASS

```
```ruby
# app/controllers/articles_controller.rb
class ArticlesController < ApplicationController
  def index
    @articles = Article.order('created_at DESC').page(params[:page]).per(10)
  end
end
```

Make sure to add Kaminari to your Gemfile and run `bundle install`:

```ruby
# Gemfile
gem 'kaminari'
```

Then run:

```bash
bundle install
rails generate kaminari:install
```
```


---
## E2 (Category E)

**Prompt:** Add file upload support to the `Article` model using Rails ActiveStorage, allowing a single attached image called `cover_image`.


### qwen3:8b — run 1 | executes=True | behavior=PASS

```
```ruby
# app/models/article.rb
class Article < ApplicationRecord
  has_one_attached :cover_image
end
```

```ruby
# db/migrate/20250101010200_create_attachments.rb
class CreateAttachments < ActiveRecord::Migration[6.1]
  def change
    create_table :active_storage_attachments do |t|
      t.string "name", null: false
      t.json "metadata"
      t.string "service_name", null: false
      t.bigint "blob_id", null: false
      t.bigint "record_id", null: false
      t.string "record_type", null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false

      t.index ["blob_id", "record_type", "record_id"], name: "index_attachments_on_blob_and_record"
      t.index ["record_type", "record_id"], name: "index_attachments_on_record"
    end
  end
end
```

```ruby
# db/migrate/20250101010300_create_active_storage_blobs.rb
class CreateActiveStorageBlobs < ActiveRecord::Migration[6.1]
  def change
    create_table :active_storage_blobs do |t|
      t.string "key", null: false
      t.string "name"
      t.string "service_name", null: false
      t.json "metadata"
      t.string "content_type"
      t.text "blob_data"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false

      t.index ["key"], name: "index_active_storage_blobs_on_key"
    end
  end
end
```

```ruby
# app/controllers/articles_controller.rb
class ArticlesController < ApplicationController
  def new
    @article = Article.new
  end

  def create
    @article = Article.new(article_params)
    if @article.save
      redirect_to @article, notice: "Article was successfully created."
    else
      render :new
    end
  end

  private

  def article_params
    params.require(:article).permit(:title, :content, :cover_image)
  end
end
```

```erb
<!-- app/views/articles/new.html.erb -->
<%= form_with(model: @article, local: true) do |form| %>
  <div>
    <%= form.label :title %>
    <%= form.text_field :title %>
  </div>

  <div>
    <%= form.label :content %>
    <%= form.text_area :content %>
  </div>

  <div>
    <%= form.label :cover_image, "Cover Image" %>
    <%= form.file_field :cover_image %>
  </div>

  <div>
    <%= form.submit %>
  </div>
<% end %>
```

```erb
<!-- app/views/articles/show.html.erb -->
<h1><%= @article.title %></h1>
<p><%= @article.content %></p>

<% if @article.cover_image.attached? %>
  <p><%= image_tag @article.cover_image %></p>
<% end %>
```
```


### qwen3:8b — run 2 | executes=True | behavior=PASS

```
```ruby
# app/models/article.rb
class Article < ApplicationRecord
  has_one_attached :cover_image
end
```

```ruby
# app/controllers/articles_controller.rb
class ArticlesController < ApplicationController
  def new
    @article = Article.new
  end

  def create
    @article = Article.new(article_params)
    if @article.save
      redirect_to @article, notice: 'Article was successfully created.'
    else
      render :new
    end
  end

  def show
    @article = Article.find(params[:id])
  end

  private

  def article_params
    params.require(:article).permit(:title, :content, :cover_image)
  end
end
```

```erb
<!-- app/views/articles/new.html.erb -->
<%= form_with model: @article do |form| %>
  <div class="field">
    <%= form.label :title %>
    <%= form.text_field :title %>
  </div>

  <div class="field">
    <%= form.label :content %>
    <%= form.text_area :content %>
  </div>

  <div class="field">
    <%= form.label :cover_image, "Cover Image" %>
    <%= form.file_field :cover_image %>
  </div>

  <div class="actions">
    <%= form.submit %>
  </div>
<% end %>
```

```erb
<!-- app/views/articles/show.html.erb -->
<h1><%= @article.title %></h1>
<p><%= @article.content %></p>

<% if @article.cover_image.attached? %>
  <p><%= image_tag @article.cover_image %></p>
<% end %>
```
```


### qwen3:8b — run 3 | executes=True | behavior=PASS

```
```ruby
# app/models/article.rb
class Article < ApplicationRecord
  has_one_attached :cover_image
end
```

```ruby
# config/routes.rb
Rails.application.routes.draw do
  resources :articles, only: [:index, :show, :new, :create, :edit, :update, :destroy]
end
```

```erb
<!-- app/views/articles/_form.html.erb -->
<%= form_with(model: article, local: true) do |form| %>
  <div class="field">
    <%= form.label :title %>
    <%= form.text_field :title %>
  </div>

  <div class="field">
    <%= form.label :body %>
    <%= form.text_area :body %>
  </div>

  <div class="field">
    <%= form.label :cover_image, "Cover Image" %>
    <%= form.file_field :cover_image %>
  </div>

  <div class="actions">
    <%= form.submit %>
  </div>
<% end %>
```

```erb
<!-- app/views/articles/show.html.erb -->
<h1><%= @article.title %></h1>
<p><%= @article.body %></p>

<% if @article.cover_image.attached? %>
  <%= image_tag @article.cover_image.url %>
<% end %>
```
```


---
## E3 (Category E)

**Prompt:** Add a fuzzy/partial-match search scope to the `Article` model using the ransack gem, searching across the `title` and `body` fields.


### qwen3:8b — run 1 | executes=True | behavior=RESULT: FAIL: exception TypeError: wrong argument type Class (expected Module)

```
```ruby
# app/models/article.rb
class Article < ApplicationRecord
  include Ransack::Search

  def self.search(query)
    if query.present?
      search_params = {
        title_or_body_cont: query
      }
      ransack(search_params).order(:created_at).reverse
    else
      all.order(:created_at).reverse
    end
  end
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=RESULT: FAIL: exception TypeError: wrong argument type Class (expected Module)

```
```ruby
# app/models/article.rb
class Article < ApplicationRecord
  include Ransack::Search

  def self.search(query)
    if query.present?
      search_params = {
        title_or_body_cont: query
      }
      ransack(search_params).order(created_at: :desc)
    else
      all.order(created_at: :desc)
    end
  end
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=RESULT: FAIL: exception NameError: uninitialized constant Ransack::Scoping

```
```ruby
# app/models/article.rb
class Article < ApplicationRecord
  include Ransack::Scoping

  def self.ransackable_attributes(_scope)
    %w[title body]
  end

  def self.ransackable_associations(_scope)
    []
  end

  scope :fuzzy_search, ->(query) {
    where("title ILIKE :query OR body ILIKE :query", query: "%#{query}%")
  }
end
```

Usage example:

```ruby
Article.fuzzy_search("rails")
```
```


---
## F1 (Category F)

**Prompt:** Add a has_many :through association: a `Doctor` has_many :patients, through: :appointments, and an `Appointment` belongs_to both a `Doctor` and a `Patient`. Write the three model class bodies.


### qwen3:8b — run 1 | executes=True | behavior=PASS

```
```ruby
class Doctor < ApplicationRecord
  has_many :appointments
  has_many :patients, through: :appointments
end

class Patient < ApplicationRecord
  has_many :appointments
  has_many :doctors, through: :appointments
end

class Appointment < ApplicationRecord
  belongs_to :doctor
  belongs_to :patient
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=PASS

```
```ruby
class Doctor < ApplicationRecord
  has_many :appointments
  has_many :patients, through: :appointments
end

class Patient < ApplicationRecord
  has_many :appointments
  has_many :doctors, through: :appointments
end

class Appointment < ApplicationRecord
  belongs_to :doctor
  belongs_to :patient
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=PASS

```
```ruby
class Doctor < ApplicationRecord
  has_many :appointments
  has_many :patients, through: :appointments
end

class Patient < ApplicationRecord
  has_many :appointments
  has_many :doctors, through: :appointments
end

class Appointment < ApplicationRecord
  belongs_to :doctor
  belongs_to :patient
end
```
```


---
## F2 (Category F)

**Prompt:** Add a polymorphic `Comment` model (with a `body` text field) that can belong to either an `Article` or a `Post`, using Rails' polymorphic association pattern. Write the `Comment` model and the association lines needed on `Article` and `Post`.


### qwen3:8b — run 1 | executes=True | behavior=PASS

```
```ruby
# == Schema Information
#
# Table name: comments
#
#  id         :integer          not null, primary key
#  body       :text            not null
#  commentable_id :integer      not null
#  commentable_type :string     not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class Comment < ApplicationRecord
  belongs_to :commentable, polymorphic: true
end

class Article < ApplicationRecord
  has_many :comments, as: :commentable
end

class Post < ApplicationRecord
  has_many :comments, as: :commentable
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=PASS

```
```ruby
# == Schema Information
#
# Table name: comments
#
#  id         :integer          primary key
#  body       :text
#  commentable_type :string
#  commentable_id :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class Comment < ApplicationRecord
  belongs_to :commentable, polymorphic: true
end

class Article < ApplicationRecord
  has_many :comments, as: :commentable
end

class Post < ApplicationRecord
  has_many :comments, as: :commentable
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=PASS

```
```ruby
# == Schema Information
#
# Table name: comments
#
#  id         :integer          not null, primary key
#  body       :text            not null
#  commentable_type :string     not null
#  commentable_id :integer     not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class Comment < ApplicationRecord
  belongs_to :commentable, polymorphic: true
end
```

```ruby
class Article < ApplicationRecord
  has_many :comments, as: :commentable
end
```

```ruby
class Post < ApplicationRecord
  has_many :comments, as: :commentable
end
```
```


---
## F3 (Category F)

**Prompt:** Add a callback to the `Order` model that sets `shipped_at` to the current time, but only when the `status` is changed to "shipped", and only after the record has actually been saved to the database.


### qwen3:8b — run 1 | executes=True | behavior=RESULT: FAIL: set_on_transition=false stable_on_noop=true ts1=nil ts2=nil

```
```ruby
class Order < ApplicationRecord
  after_save :set_shipped_at_if_shipped

  private

  def set_shipped_at_if_shipped
    return unless status == 'shipped'
    self.shipped_at = Time.current
  end
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=RESULT: FAIL: set_on_transition=false stable_on_noop=true ts1=nil ts2=nil

```
```ruby
class Order < ApplicationRecord
  after_save :set_shipped_at_if_shipped

  private

  def set_shipped_at_if_shipped
    return unless status == 'shipped'
    self.shipped_at = Time.current
  end
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=RESULT: FAIL: set_on_transition=false stable_on_noop=true ts1=nil ts2=nil

```
```ruby
class Order < ApplicationRecord
  after_save :set_shipped_at_if_shipped

  private

  def set_shipped_at_if_shipped
    return unless status == 'shipped'
    self.shipped_at = Time.current
  end
end
```
```


---
## F4 (Category F)

**Prompt:** Extract shared 'archivable' behavior into a reusable Rails Concern: an `archived` boolean flag, an `archive!` method that sets it true and saves, and a `scope :active` that excludes archived records. Show the Concern module and how to include it in the `Article` and `Order` models.


### qwen3:8b — run 1 | executes=True | behavior=PASS

```
```ruby
# app/models/concerns/archivable.rb
module Archivable
  extend ActiveSupport::Concern

  included do
    attribute :archived, :boolean, default: false
    scope :active, -> { where(archived: false) }
  end

  def archive!
    update!(archived: true)
  end
end
```

```ruby
# app/models/article.rb
class Article < ApplicationRecord
  include Archivable
end
```

```ruby
# app/models/order.rb
class Order < ApplicationRecord
  include Archivable
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=PASS

```
```ruby
# app/concerns/archivable.rb
module Archivable
  extend ActiveSupport::Concern

  included do
    attribute :archived, :boolean, default: false

    scope :active, -> { where(archived: false) }

    def archive!
      update!(archived: true)
    end
  end
end
```

```ruby
# app/models/article.rb
class Article < ApplicationRecord
  include Archivable
end
```

```ruby
# app/models/order.rb
class Order < ApplicationRecord
  include Archivable
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=PASS

```
```ruby
# app/concerns/archivable.rb
module Archivable
  extend ActiveSupport::Concern

  included do
    attribute :archived, :boolean, default: false
    scope :active, -> { where(archived: false) }
  end

  def archive!
    update!(archived: true)
  end
end
```

```ruby
# app/models/article.rb
class Article < ApplicationRecord
  include Archivable
end
```

```ruby
# app/models/order.rb
class Order < ApplicationRecord
  include Archivable
end
```
```


---
## F5 (Category F)

**Prompt:** Write the strong parameters method in `ArticlesController` for a form that creates an `Article` and its associated `Comments` in one submission using nested attributes, permitting only the appropriate fields and not over-permitting.


### qwen3:8b — run 1 | executes=True | behavior=PASS

```
```ruby
def article_params
  params.require(:article).permit(
    :title, :content, :published,
    comments_attributes: [:id, :content, :_destroy]
  )
end
```

This method ensures only permitted fields are accepted, and properly handles nested `comments` with `:_destroy` for soft deletion.
```


### qwen3:8b — run 2 | executes=True | behavior=PASS

```
```ruby
def article_params
  params.require(:article).permit(
    :title, :content, :published,
    comments_attributes: [:id, :content, :_destroy]
  )
end
```

This method permits the necessary fields for an `Article` and its associated `Comments`, ensuring that only the permitted attributes are allowed, and preventing over-permission. The `:_destroy` key is used to support deletion of associated comments via nested attributes.
```


### qwen3:8b — run 3 | executes=True | behavior=PASS

```
```ruby
# app/controllers/articles_controller.rb
class ArticlesController < ApplicationController
  def article_params
    params.require(:article).permit(
      :title, :content, :published,
      comments_attributes: [:id, :content, :_destroy]
    )
  end
end
```

This method ensures that only the permitted fields for `Article` and its nested `Comments` are allowed, and it prevents over-permission by explicitly listing the allowed attributes.
```


---
## G1 (Category G)

**Prompt:** Write a Minitest integration or controller test for a Rails `PostsController#publish` action. The action transitions a post's status to "published", sets `published_at` to the current time, and redirects back to the post with a flash notice on success.


### qwen3:8b — run 1 | executes=True | behavior=FAIL: does not pass even against the correct reference implementation ({'runs': 1, 'assertions': 0, 'failures': 0, 'errors': 1, 'skips': 0}) | false_positive=False

```
```ruby
# test/integration/posts_integration_test.rb
require 'test_helper'

class PostsIntegrationTest < ActionDispatch::IntegrationTest
  test 'publish a post successfully' do
    post = posts(:draft)

    assert_redirected_to post_path(post)
    assert_equal 'Post published successfully.', flash[:notice]
  end
end
```

```ruby
# test/controllers/posts_controller_test.rb
require 'test_helper'

class PostsControllerTest < ActionDispatch::IntegrationTest
  test 'publish action sets published_at and redirects with notice' do
    post = posts(:draft)

    patch publish_post_path(post), params: { post: { id: post.id } }

    post.reload
    assert_equal 'published', post.status
    assert_not_nil post.published_at
    assert_redirected_to post_path(post)
    assert_equal 'Post published successfully.', flash[:notice]
  end
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=FAIL: does not pass even against the correct reference implementation ({'runs': 1, 'assertions': 1, 'failures': 1, 'errors': 0, 'skips': 0}) | false_positive=False

```
```ruby
# test/controllers/posts_controller_test.rb
require "test_helper"

class PostsControllerTest < ActionDispatch::IntegrationTest
  test "should publish a post and redirect with flash notice" do
    post = posts(:one)
    assert_equal "draft", post.status

    patch publish_post_path(post), params: { post: { status: "published" } }

    post.reload
    assert_equal "published", post.status
    assert_not_nil post.published_at
    assert_redirected_to post_path(post)
    assert_equal "Post was successfully published.", flash[:notice]
  end
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=FAIL: does not pass even against the correct reference implementation ({'runs': 1, 'assertions': 1, 'failures': 1, 'errors': 0, 'skips': 0}) | false_positive=False

```
```ruby
# test/integration/posts_controller_test.rb
require "test_helper"

class PostsControllerTest < ActionDispatch::IntegrationTest
  test "should publish a post and redirect with notice" do
    post = posts(:one)
    assert_equal "draft", post.status

    patch publish_post_path(post), params: { post: { status: "published" } }

    assert_redirected_to post_path(post)
    assert_equal "Post published successfully.", flash[:notice]
    post.reload
    assert_equal "published", post.status
    assert_not_nil post.published_at
  end
end
```
```


---
## G2 (Category G)

**Prompt:** Write a Minitest model test for a Rails `User` model with these validations: `email` must be present and unique (case-insensitive), `username` must be present with length between 3 and 20, and `age` must be numeric but may be nil.


### qwen3:8b — run 1 | executes=True | behavior=PASS: correctly passes against correct implementation and fails against broken implementation | false_positive=False

```
```ruby
# test/models/user_test.rb
require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test 'email is required and must be unique (case-insensitive)' do
    user = User.new(username: 'test', age: 25)
    assert user.invalid?, 'User should be invalid without email'
    assert user.errors[:email].present?, 'Email error should be present'

    user.email = 'Test@example.com'
    assert user.save, 'User should be valid with email'

    duplicate_user = User.new(email: 'test@example.com', username: 'test', age: 25)
    assert duplicate_user.invalid?, 'Duplicate email should be invalid'
  end

  test 'username is required and must be between 3 and 20 characters' do
    user = User.new(email: 'test@example.com', age: 25)
    assert user.invalid?, 'User should be invalid without username'
    assert user.errors[:username].present?, 'Username error should be present'

    user.username = 'a' * 2
    assert user.invalid?, 'Too short username should be invalid'
    assert user.errors[:username].present?, 'Username error should be present'

    user.username = 'a' * 21
    assert user.invalid?, 'Too long username should be invalid'
    assert user.errors[:username].present?, 'Username error should be present'

    user.username = 'validusername'
    assert user.save, 'Valid username should be valid'
  end

  test 'age must be numeric and may be nil' do
    user = User.new(email: 'test@example.com', username: 'validusername')
    assert user.save, 'User should be valid without age'

    user.age = 'twenty'
    assert user.invalid?, 'Non-numeric age should be invalid'
    assert user.errors[:age].present?, 'Age error should be present'

    user.age = 30
    assert user.save, 'Numeric age should be valid'
  end
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=FAIL: does not pass even against the correct reference implementation ({'runs': 7, 'assertions': 11, 'failures': 1, 'errors': 6, 'skips': 0}) | false_positive=False

```
```ruby
# test/models/user_test.rb
require 'test_helper'

class UserTest < Minitest::Test
  def setup
    @user = User.new
  end

  def test_email_required
    assert @user.invalid?
    assert_match /email can't be blank/, @user.errors.full_messages
  end

  def test_email_unique_case_insensitive
    user1 = User.create!(email: 'test@example.com')
    user2 = User.new(email: 'TEST@EXAMPLE.COM')
    assert user2.invalid?
    assert_match /email has already been taken/, user2.errors.full_messages
  end

  def test_email_format
    @user.email = 'invalid-email'
    assert @user.invalid?
    assert_match /email is invalid/, @user.errors.full_messages
  end

  def test_username_required
    @user.username = ''
    assert @user.invalid?
    assert_match /username can't be blank/, @user.errors.full_messages
  end

  def test_username_length
    @user.username = 'a' * 21
    assert @user.invalid?
    assert_match /username is too long/, @user.errors.full_messages

    @user.username = 'a' * 2
    assert @user.invalid?
    assert_match /username is too short/, @user.errors.full_messages
  end

  def test_age_numeric
    @user.age = 'thirty'
    assert @user.invalid?
    assert_match /age is not a number/, @user.errors.full_messages
  end

  def test_age_can_be_nil
    @user.age = nil
    assert @user.valid?
  end
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=FAIL: does not pass even against the correct reference implementation ({'runs': 7, 'assertions': 17, 'failures': 3, 'errors': 1, 'skips': 0}) | false_positive=False

```
```ruby
# test/models/user_test.rb
require "test_helper"

class UserTest < Minitest::Test
  def setup
    @user = User.new
  end

  def test_email_required
    @user.email = ""
    assert @user.invalid?
    assert_includes @user.errors[:email], "can't be blank"
  end

  def test_email_unique_case_insensitive
    User.create!(email: "test@example.com")
    @user.email = "TEST@EXAMPLE.COM"
    assert @user.invalid?
    assert_includes @user.errors[:email], "has already been taken"
  end

  def test_email_not_unique
    @user.email = "unique@example.com"
    assert @user.valid?
  end

  def test_username_required
    @user.username = ""
    assert @user.invalid?
    assert_includes @user.errors[:username], "can't be blank"
  end

  def test_username_length
    @user.username = "ab"
    assert @user.invalid?
    assert_includes @user.errors[:username], "is too short (minimum is 3 characters)"

    @user.username = "a" * 21
    assert @user.invalid?
    assert_includes @user.errors[:username], "is too long (maximum is 20 characters)"
  end

  def test_age_numeric
    @user.age = "twenty"
    assert @user.invalid?
    assert_includes @user.errors[:age], "must be a number"
  end

  def test_age_can_be_nil
    @user.age = nil
    assert @user.valid?
  end
end
```
```


---
## R1 (Category H)

**Prompt:** Write a Ruby method that builds a hash from local variables `name`, `age`, and `email`.


### qwen3:8b — run 1 | executes=True | behavior=RESULT: FAIL: could not call method either style: ArgumentError: wrong number of arguments (given 3, expected 0) | idiom=pre-3.1-explicit

```
```ruby
def build_user_hash
  {
    name: name,
    age: age,
    email: email
  }
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=RESULT: FAIL: could not call method either style: ArgumentError: wrong number of arguments (given 3, expected 0) | idiom=pre-3.1-explicit

```
```ruby
def build_user_hash
  { name: name, age: age, email: email }
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=RESULT: FAIL: could not call method either style: ArgumentError: wrong number of arguments (given 3, expected 0) | idiom=pre-3.1-explicit

```
```ruby
def build_user_hash
  { name: name, age: age, email: email }
end
```
```


---
## R2 (Category H)

**Prompt:** Define an immutable Point value object with `x` and `y` attributes in Ruby.


### qwen3:8b — run 1 | executes=True | behavior=PASS | idiom=pre-3.2-hand-rolled-class

```
```ruby
class Point
  attr_reader :x, :y

  def initialize(x, y)
    @x = x
    @y = y
  end

  def self.from_array(array)
    new(array[0], array[1])
  end

  def to_h
    { x: x, y: y }
  end

  def ==(other)
    other.is_a?(Point) && x == other.x && y == other.y
  end

  def hash
    [x, y].hash
  end
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=PASS | idiom=pre-3.2-hand-rolled-class

```
```ruby
class Point
  attr_reader :x, :y

  def initialize(x, y)
    @x = x
    @y = y
  end

  def ==(other)
    return false unless other.is_a?(Point)
    x == other.x && y == other.y
  end

  def hash
    [x, y].hash
  end

  def to_s
    "#<Point:0x#{object_id} x=#{x} y=#{y}>"
  end
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=PASS | idiom=pre-3.2-hand-rolled-class

```
```ruby
class Point
  attr_reader :x, :y

  def initialize(x, y)
    @x = x
    @y = y
  end

  def ==(other)
    other.is_a?(Point) && @x == other.x && @y == other.y
  end

  def hash
    [@x, @y].hash
  end
end
```
```


---
## R3 (Category H)

**Prompt:** Write a Ruby method `wrapper` that accepts any arguments and forwards all of them, unnamed, to another method called `target`.


### qwen3:8b — run 1 | executes=True | behavior=RESULT: FAIL: got args=[1, 2, {:foo=>"bar"}] kwargs={} block="blockval" | idiom=pre-3.2-explicit-splat-args-only

```
```ruby
def wrapper(*args, &block)
  target(*args, &block)
end
```
```


### qwen3:8b — run 2 | executes=True | behavior=RESULT: FAIL: got args=[1, 2, {:foo=>"bar"}] kwargs={} block=nil | idiom=pre-3.2-explicit-splat-args-only

```
```ruby
def wrapper(*args)
  target(*args)
end
```
```


### qwen3:8b — run 3 | executes=True | behavior=PASS | idiom=pre-3.2-explicit-splat

```
```ruby
def wrapper(*args, **kwargs, &block)
  target(*args, **kwargs, &block)
end
```
```


---
## R4 (Category H)

**Prompt:** Write a Ruby block that doubles each number in an array using the implicit block parameter shorthand, without naming the parameter explicitly.


### qwen3:8b — run 1 | executes=True | behavior=PASS | idiom=explicit-named-param

```
```ruby
[1, 2, 3].map { |n| n * 2 }
```
```


### qwen3:8b — run 2 | executes=True | behavior=PASS | idiom=explicit-named-param

```
```ruby
[1, 2, 3].map { |n| n * 2 }
```
```


### qwen3:8b — run 3 | executes=True | behavior=PASS | idiom=explicit-named-param

```
```ruby
[1, 2, 3].map { |n| n * 2 }
```
```
