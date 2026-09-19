# frozen_string_literal: true

module Dwar
  class ApplicationRecord < ActiveRecord::Base
    # The engine must not claim the single primary_abstract_class slot (Rails
    # 8.1 raises if more than one exists per application): the host app's own
    # ApplicationRecord owns it. Engine models only need to be abstract.
    self.abstract_class = true
  end
end
