Rails.application.routes.draw do
  post "webhooks/payments", to: "webhooks#payments"
end