require_relative "lib/activesupport_json_escape/version"

Gem::Specification.new do |spec|
  spec.name = "activesupport_json_escape"
  spec.version = ActiveSupportJsonEscape::VERSION
  spec.authors = ["Benjamin Quorning"]
  spec.email = ["bquorning@zendesk.com"]

  spec.summary = "Faster HTML entity and JS separator escaping for ActiveSupport JSON encoding"
  spec.description = "Drop-in ActiveSupport::JSON encoder that replaces the Ruby gsub! calls for escaping HTML " \
                     "entities (<, >, &) and JavaScript line/paragraph separators (U+2028, U+2029) with a C extension."
  spec.homepage = "https://github.com/zendesk/activesupport_json_escape"
  spec.license = "Apache License Version 2.0"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"

  spec.files = Dir["lib/**/*.rb", "ext/**/*.{c,h,rb}", "README.md", "LICENSE.txt", "CODE_OF_CONDUCT.md"]
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/activesupport_json_escape/extconf.rb"]

  spec.add_dependency "json", ">= 2.15.2"
  spec.add_dependency "activesupport", ">= 8.1"
end
