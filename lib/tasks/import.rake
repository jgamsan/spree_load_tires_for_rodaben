namespace :products do

  desc "Import products to spree database."
  task :to_rodaben_gane => :environment do
    require 'import_tires_from_gane'
    ImportTiresFromGane.new.run
  end

  desc "Import products from Eurotyre to spree database."
  task :to_rodaben_eurotyre => :environment do
    require 'import_tires_from_eurotyre'
    ImportTiresFromEurotyre.new.run
  end

  desc "Delete products from all suppliers no updated in 1 day minimun"
  task :clean_rodaben => :environment do
    require 'delete_tires_no_updated'
    DeleteTiresNoUpdated.new.run
  end
end
