# frozen_string_literal: true

Dwar::Engine.routes.draw do
  root to: "admin/flags#index"

  namespace :admin do
    resources :flags, only: [:index, :new, :create, :edit, :update, :destroy]
    resources :groups, only: [:index]
    resources :memberships, only: [:index]
    resources :users, only: [:index]
  end
end
