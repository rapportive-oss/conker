Gem::Specification.new do |s|
  s.name = 'environment_variables'
  s.authors = ['Sam Stokes', 'Conrad Irwin', 'Lee Mallabone', 'Martin Kleppmann']
  s.email = 'supportive@rapportive.com'
  s.version = '0.10.1'
  s.summary = %q{Environment variables.} # TODO
  s.description = "Library for dealing with environment variables." # TODO
  s.homepage = "https://github.com/rapportive/rapportive_ruby"
  s.date = Date.today.to_s
  s.files = `git ls-files`.split("\n")
  s.require_paths = %w(lib)
  s.add_dependency 'activesupport'
end
