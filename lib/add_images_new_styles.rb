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
    @list_folders = Dir.entries(@wd) - ["..", "."]
  end

  def add_folders
    j = 1
    for i in 2..@list_folders.count
      folder = @wd + "/#{@list_folders[i]}"
      unless Dir.exist?(folder + "/ceelabel")
        begin
          a = (Dir.entries(folder + "/product") - ["..", "."]).first
          ext = File.extname(a)
          name = File.basename(a, ext)
          create_ceelabel(folder, name, ext)
          create_newmark(folder, name, ext)
          create_offertmark(folder, name, ext)
          j += 1
          print "Vamos por la carpeta #{i}. Creada carpeta #{j}\r".white.on_blue unless Rails.env.production?
        rescue Exception => e
          puts "Error en la carpeta #{i}".white.on_red unless Rails.env.production?
        end

      end
    end
  end

  def create_ceelabel(folder, name, ext)
    Dir.mkdir(folder + "/ceelabel")
    FileUtils.cp(@image, folder + "/ceelabel/#{name}.png")
  end

  def create_newmark(folder, name, ext)
    Dir.mkdir(folder + "/newmark")
    image = MiniMagick::Image.open(folder + "/product/" + "#{name}.#{ext}")
    result = image.composite(MiniMagick::Image.open(@new_image), "png") do |c|
      c.gravity "NorthWest"
    end
    result.resize "240x240"
    result.write(folder + "/newmark/#{name}.png")
  end

  def create_offertmark(folder, name, ext)
    Dir.mkdir(folder + "/offertmark")
    image = MiniMagick::Image.open(folder + "/product/" + "#{name}.#{ext}")
    result = image.composite(MiniMagick::Image.open(@offert_image), "png") do |c|
      c.gravity "NorthWest"
    end
    result.resize "240x240"
    result.write(folder + "/offertmark/#{name}.png")
  end

end