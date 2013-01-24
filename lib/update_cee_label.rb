class UpdateCeeLabel
  def initialize
    @products = nil
    @default = "#{Rails.root}/app/assets/images/default.png"
    @fuel_options = Hash["A", "-14-55", "B", "-13-33", "C", "-13-11", "D", "-13+11", "E", "-13+33", "F", "-13+55", "G", "-13+77"]
    @wet_options = Hash["A", "+103-53", "B", "+103-31", "C", "+103-9", "D", "+103+13", "E", "+103+35", "F", "+103+56", "G", "+103+78"]
  end

  def run
    get_products
    rewrite_cee_label
  end

  def get_products
    @products = Spree::Product.in_cars(["4", "5", "6", "7", "8"])
  end

  def rewrite_cee_label
    @products.each do |p|
      unless p.master.cee_label == '????'
        imagen = p.master.images.first
        n = imagen.attachment.path(:product)
        name = File.basename(n)
        wd = File.dirname(n)
        fuel = p.master.tire_fuel_consumption.name
        wet = p.master.tire_wet_grip.name
        noise_db = p.master.tire_rolling_noise_db
        noise_wave = p.master.tire_rolling_noise_wave
        i = MiniMagick::Image.open(@default)
        result = i.composite(MiniMagick::Image.open("#{Rails.root}/app/assets/images/#{fuel.downcase}.png"), "png") do |c|
          c.gravity "center"
          c.geometry @fuel_options[fuel]
        end
        result = result.composite(MiniMagick::Image.open("#{Rails.root}/app/assets/images/#{wet.downcase}.png", "png")) do |c|
          c.gravity "center"
          c.geometry @wet_options[wet]
        end
        result = result.composite(MiniMagick::Image.open("#{Rails.root}/app/assets/images/emision_ruido_#{noise_wave}.png", "png")) do |c|
          c.gravity "center"
          c.geometry "-30+165"
        end
        result.combine_options do |c|
          c.gravity "center"
          c.pointsize '30'
          c.draw "text 60,168 '#{noise_db}'"
          c.font 'arial'
          c.fill "#FFFFFF"
        end
        new_name = File.basename(n, File.extname(n)) + ".png"
        result.write(File.join(File.dirname(imagen.attachment.path(:ceelabel)), new_name))
      end
    end
  end
end