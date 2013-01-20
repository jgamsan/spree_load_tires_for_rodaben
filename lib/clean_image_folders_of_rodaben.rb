class CleanImageFoldersOfRodaben
  def initialize()
    @wd = "#{Rails.root}/public/spree/products"
  end

  def run
    total_folders = Dir.entries(@wd)
    total_images = Spree::Image.all
  end

end