class AddImagesNewStyles
  def initialize
    @wd = "#{Rails.root}/public/spree/products"
    @image = "#{Rails.root}/app/assets/images/base_etiqueta.png"
    @offert_image = "#{Rails.root}/app/assets/images/yellow-m.png"
    @new_image = "#{Rails.root}/app/assets/images/blue-m.png"
    @list_folders = []
  end

  def run
    get_total_folders
    add_folders
  end

  def get_total_folders
    @list_folders = Dir.entries(@wd)
  end

  def add_folders
    for i in 2..@list_folders.count
      folder = @wd + "/#{@list_folders[i]}"
      unless Dir.exist?(folder + "/ceelabel")
        create_ceelabel(folder)
        create_newmark(folder)
        create_offertmark(folder)
        puts "Creada carpeta no existente #{i}".white.on_blue unless Rails.env.production?
      end
    end
  end

  def create_ceelabel(folder)
    Dir.mkdir(folder + "/ceelabel")
    FileUtils.cp(@image, folder + '/ceelabel/default.png')
  end

  def create_newmark(folder)
    Dir.mkdir(folder + "/newmark")
    image = MiniMagick::Image.open(folder + "/product/" + (Dir.entries(folder + "/product") - ["..", "."]).first)
    result = image.composite(MiniMagick::Image.open(@new_image), "png") do |c|
      c.gravity "NorthWest"
    end
    result.resize "240x240"
    result.write(folder + "/newmark/default.png")
  end

  def create_offertmark(folder)
    Dir.mkdir(folder + "/offertmark")
    image = MiniMagick::Image.open(folder + "/product/" + (Dir.entries(folder + "/product") - ["..", "."]).first)
    result = image.composite(MiniMagick::Image.open(@offert_image), "png") do |c|
      c.gravity "NorthWest"
    end
    result.resize "240x240"
    result.write(folder + "/offertmark/default.png")
  end

end