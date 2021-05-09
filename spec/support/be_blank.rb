RSpec::Matchers.define :be_blank do
  match do |string|
    (string || "") == ""
  end
end
