Gem::Specification.new do |s|
  s.name               = "thin_serializer"
  s.version            = "0.0.1"

  s.authors = ["Jan Berdajs"]
  s.date = %q{2014-04-03}
  s.email       = ["mrbrdo@gmail.com"]
  s.homepage    = "https://github.com/mrbrdo/thin_serializer"
  s.files = Dir["{app,config,db,lib}/**/*"] + ["MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]
  s.require_paths = ["lib"]
  s.summary = %q{Ruby JSON serialization library optimized for performance}

  s.add_dependency 'activerecord'
  s.add_development_dependency 'pry'
end

