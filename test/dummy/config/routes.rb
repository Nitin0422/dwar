Rails.application.routes.draw do
  mount Dwar::Engine => "/dwar"

  # Dev-only harness for the T11 user picker (see UserPickerDemoController).
  get "/user_picker_demo", to: "user_picker_demo#index"
  get "/user_picker_demo/user_picker.js", to: "user_picker_demo#user_picker_js"
end
