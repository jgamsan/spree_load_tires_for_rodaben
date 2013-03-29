# encoding: UTF-8
require 'csv'

class ImportTiresOfMoto

  def initialize()
    @directory = "#{Rails.root}/vendor/products"
    @file = "datos.csv"
    @image_wd = "#{Rails.root}/vendor/products/images/pic/"
    @send_file = "listado-neumaticos-no-incorporados-moto.csv"
    @logger = Logger.new(File.join(@directory, 'logfile.log'))
    @created = 0
    @updated = 0
    @deleted = 0
    @readed = 0
    @total = []
    @tubes = %w(TL TT RU)
    @green_rate = Spree::TireGreenRate.find_by_cat("A").id
    @shipping_category = Spree::ShippingCategory.where("name like '%Motos%'").first.id
    I18n.locale = 'es'
  end

  def run
    load_from_csv
    send_mail
  end

  def load_from_csv
    hoy = Date.today
    no_leidos = []
    i = j = 0
    CSV.foreach(File.join(@directory, @file), encoding: "ISO-8859-1", headers: true,  col_sep: ';') do |row|
      begin
        if Spree::Variant.existe_moto_tire(row[1]) #buscar por SKU
          variante = Spree::Variant.search_moto_tire(row[1])
          cost_price = price = row[12].strip.gsub(/,/, '.').to_f
          variante.update_attributes(
                  :price_in_offert => price,
                  :price => price,
                  :cost_price => cost_price,
                  :tire_load_code_id => set_load_code(row),
                  :tire_position => set_position(row),
                  :tire_rf => set_rf(row),
                  :tire_fuel_consumption_id => nil,
                  :tire_wet_grip_id => nil,
                  :tire_rolling_noise_db => nil,
                  :tire_rolling_noise_wave => nil
                  )
          if variante.images.empty?
            add_image(variante, @image_wd, row[13])
          elsif product.images.first.attachment_file_name != row[13]
            change_image(variante, @image_wd, row[13])
          end
          @updated += 1
          puts "Actualizado #{row[2]}".white.on_blue unless Rails.env.production?
        else
          i += 1
          # crear uno nuevo
          product = Spree::Product.new
          product.name = row[2] + (row[16].nil? ? "" : row[16])
          product.permalink = product.name.downcase.gsub(/\s+/, '-').gsub(/[^a-zA-Z0-9_]+/, '-')
          product.sku = row[1]
          product.available_on = hoy - 1.day
          product.supplier_id = 2028
          
          product.show_in_offert = false
          cost_price = price = row[12].strip.gsub(/,/, '.').to_f
          
          variant = Spree::Variant.new
          
          variant.price = price
          variant.cost_price = price
          variant.count_on_hand = 6
          variant.price_in_offert = price
          
          variant.tire_width_id = set_width(row)
          variant.tire_serial_id = set_serial(row)
          variant.tire_innertube_id = set_innertube(row)
          variant.tire_load_code_id = set_load_code(row)
          variant.tire_speed_code_id = set_speed_code(row)
          variant.tire_position = set_position(row)
          variant.tire_rf = set_rf(row)
          variant.tire_green_rate_id = 1
          variant.tire_fuel_consumption_id = nil
          variant.tire_wet_grip_id = nil
          variant.tire_rolling_noise_db = nil
          variant.tire_rolling_noise_wave = nil
          product.shipping_category_id = @shipping_category
          product.taxons << Spree::Taxon.find(9) #cargar categoria
          product.taxons << Spree::Taxon.find(set_brand(row)) #cargar marca
          product.master = variant
          if product.save!
            puts "Creado articulo #{row[2]}".white.on_blue unless Rails.env.production?
            j += 1
          end
          add_image(variant, @image_wd, row[13])
          variant = nil
          product = nil
          @created += 1
        end
      rescue Exception => e
        no_leidos << [row[1], row[2], row[8], row[12], row[17], row[19], row[21], row[23], e]
        @logger.info("#{row[6]}, #{row[0]}, #{row[1]}, #{row[2]}, #{row[3]}")
        @logger.error("#{e.class.name}: #{e.message}")
        @logger.error(e.backtrace * "\n")
        @logger.info '=' * 50
        next
      end
    end
    unless no_leidos.empty?
      headers_row = ["SKU", "Nombre", "Marca", "Precio", "Ancho", "Perfil", "Llanta", "IV", "Error"]
      CSV.open(File.join(@directory, @send_file), "wb", {headers: headers_row, write_headers: true}) do |row|
        no_leidos.each do |element|
          row << element
        end
      end
    end
  end

  def send_mail
    begin
      Spree::NotifyMailer.report_notification(@readed, @updated, @deleted, @created, @directory, @send_file, "MOTO").deliver
    rescue Exception => e
      logger.error("#{e.class.name}: #{e.message}")
      logger.error(e.backtrace * "\n")
    end
  end

  def set_width(row)
    #[ancho, perfil, llanta, ic, iv, marca, modelo, oferta, precio, PVP, stock]
    return nil if row[17].nil?
    ancho = Spree::TireWidth.find_by_name(row[17])
    ancho.nil? ? raise("Este ancho no existe #{row[17]}") : ancho.id
  end

  def set_serial(row)
    return nil if row[19].nil? 
    serie = Spree::TireSerial.find_by_name(row[19])
    serie.nil? ? raise("Este perfil no existe #{row[19]}") : serie.id
  end

  def set_innertube(row)
    return nil if row[21].nil?
    llanta = Spree::TireInnertube.find_by_name(row[21])
    llanta.nil? ? raise("Esta llanta no existe #{row[21]}") : llanta.id
  end

  def set_speed_code(row)
    return nil if row[23].nil?
    vel = Spree::TireSpeedCode.find_by_name(row[23])
    vel.nil? ? raise("Este Indice Velocidad no existe #{row[23]}") : vel.id
  end

  def set_brand(row)
    if row[8].nil?
      raise "Sin Marca"
    else
      if row[8].include?(" ")
        marca = row[8].split.join('-').downcase
      else
        marca = row[8].downcase
      end
      brand = Spree::Taxon.find_by_permalink("marcas/#{marca}")
      if brand.nil?
        raise("Marca #{row[8]} no esta registrada")
      else
        return brand.id
      end
    end
  end

  def add_image(variant, dir, file)
    if File.exist?(dir+file)
      img = Spree::Image.new({:attachment => File.open(dir + file), :viewable => variant}, :without_protection => true)
      img.save!
      variant.images << img
    end
  end

  def change_image(variant, dir, file)
    variant.images.delete_all
    add_image(variant, dir, file)
  end

  def set_load_code(row)
    return nil if row[22].nil?
    load_code = Spree::TireLoadCode.find_by_name(row[22])
    load_code.nil? ? raise("Este Indice de Carga no existe #{row[22]}") : load_code.id
  end

  def set_position(row)
    return 3 if row[24].nil?
    case row[24]
      when "F"
        1
      when "R"
        2
      else
        3
    end
  end

  def set_rf(row)
    return nil if row[25].nil?
    @tubes.index(row[25]) + 1
  end

end
