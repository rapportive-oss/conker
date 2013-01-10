Gem::Specification.new do |s|
  s.name = 'conker'
  s.authors = ['Sam Stokes', 'Conrad Irwin', 'Lee Mallabone', 'Martin Kleppmann']
  s.email = 'supportive@rapportive.com'
  s.version = '0.12.0'
  s.summary = %q{Conker will conquer your config.}
  s.description = "Configuration library."
  s.homepage = "https://github.com/rapportive/conker"
  s.license = 'MIT'
  s.date = Date.today.to_s
  s.files = `git ls-files`.split("\n")
  s.require_paths = %w(lib)
  s.add_dependency 'activesupport'
  s.add_dependency 'addressable'
  s.add_development_dependency 'rspec'
end
