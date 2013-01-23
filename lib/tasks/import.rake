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

  desc "Import products of moto to spree database"
  task :to_rodaben_moto => :environment do
    require 'import_tires_of_moto'
    ImportTiresOfMoto.new.run
  end

  desc "Delete folders of Rodaben Products"
  task :clean_folders_in_rodaben => :environment do
    require 'clean_image_folders_of_rodaben'
    CleanImageFoldersOfRodaben.new.run
  end

  desc "Create images for new added styles"
  task :add_images_for_new_styles => :environment do
    require 'add_images_new_styles'
    AddImagesNewStyles.new.run
  end

  desc "Update CEE label in existing products"
  task :update_ceelabel_in_rodaben => :environment do
    require 'update_cee_label'
    UpdateCeeLabel.new.run
  end

end
