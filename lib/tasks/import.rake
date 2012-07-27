namespace :products do
  
  desc "Import products to spree database."
  task :to_rodaben => :environment do
    require 'import_tires_from_gane'
    ImportTiresFromGane.new.run
  end

end
