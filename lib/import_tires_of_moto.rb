# encoding: UTF-8
require 'csv'

class ImportTiresOfMoto

  def initialize()
    @directory = "#{Rails.root}/vendor/products"
    @file = "datos.csv"
    @image_wd = "#{Rails.root}/vendor/products/images/pic/"
    @send_file = "listado-neumaticos-no-incorporados-moto.csv"
    @created = 0
    @updated = 0
    @deleted = 0
    @readed = 0
    @total = []
    @tubes = %w(TL TT RU)
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
    CSV.foreach(File.join(@directory, @file), {headers: true}) do |row|
      begin
        if Spree::Variant.existe_moto_tire(row[1]) #buscar por SKU
          variante = Spree::Variant.search_moto_tire(row[1])
          cost_price = price = row[12].to_f
#          variante.update_column(:cost_price, price)
#          variante.update_column(:price, price)
          variante.update_attributes(
                  :price_in_offert => price,
                  :price => price,
                  :cost_price => cost_price)
          product = Spree::Product.find(variante.product_id)
          if product.images.empty?
            add_image(product, @image_wd, row[13])
          elsif product.images.first.attachment_file_name != row[13]
            change_image(product, @image_wd, row[13])
          end

          @updated += 1
          puts "Actualizado #{row[2]}" unless Rails.env.production?
        else
          i += 1
          # crear uno nuevo
          product = Spree::Product.new
          product.name = row[2] + (row[16].nil? ? "" : row[16])
          product.permalink = product.name.downcase.gsub(/\s+/, '-').gsub(/[^a-zA-Z0-9_]+/, '-')
          product.sku = row[1]
          product.available_on = hoy - 1.day
          cost_price = price = row[12].to_f
          product.price = price
          product.cost_price = price
          product.price_in_offert = price
          product.show_in_offert = false
          product.supplier_id = 2028
          product.tire_width_id = set_width(row)
          product.tire_serial_id = set_serial(row)
          product.tire_innertube_id = set_innertube(row)
          product.tire_load_code_id = set_load_code(row)
          product.tire_speed_code_id = set_speed_code(row)
          product.tire_position = set_position(row)
          product.tire_rf = set_rf(row)
          product.taxons << Spree::Taxon.find(9) #cargar categoria
          product.taxons << Spree::Taxon.find(set_brand(row)) #cargar marca
          if product.save!
            puts "Creado articulo #{row[2]}" unless Rails.env.production?
            j += 1
          end
          #v = Spree::Variant.find_by_product_id(product.id)
          product.master.update_attributes(:count_on_hand => 6)
          add_image(product, @image_wd, row[13])
          v = nil
          product = nil
          @created += 1
          puts "Created es igual a #{@created}" unless Rails.env.production?
        end
      rescue Exception => e
        no_leidos << [row[1], row[2], row[8], row[12], row[17], row[19], row[21], row[23], e]
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
    if row[17].nil?
      nil
    else
      ancho = Spree::TireWidth.find_by_name(row[17])
      if ancho.nil?
        raise "Este ancho no existe #{row[17]}"
      else
        return ancho.id
      end
    end

  end

  def set_serial(row)
    if row[19].nil?
      nil
    else
      serie = Spree::TireSerial.find_by_name(row[19])
      if serie.nil?
        raise "Este perfil no existe #{row[19]}"
      else
        return serie.id
      end
    end

  end

  def set_innertube(row)
    if row[21].nil?
      nil
    else
      llanta = Spree::TireInnertube.find_by_name(row[21])
      if llanta.nil?
        raise "Esta llanta no existe #{row[21]}"
      else
        return llanta.id
      end
    end

  end

  def set_speed_code(row)
    if row[23].nil?
      nil
    else
      vel = Spree::TireSpeedCode.find_by_name(row[23])
      if vel.nil?
        raise "Este Indice Velocidad no existe #{row[23]}"
      else
        return vel.id
      end
    end
  end

  def set_brand(row)
    if row[8].nil?
      raise "Marca #{row[8]} no esta registrada"
    else
      if row[8].include?(" ")
        marca = row[8].split.join('-').downcase
      else
        marca = row[8].downcase
      end
      brand = Spree::Taxon.find_by_permalink("marcas/#{marca}")
      return brand.id
    end
  end

  def add_image(product, dir, file)
    if File.exist?(dir+file)
      type = file.split(".").last
      i = Spree::Image.new(:attachment => Rack::Test::UploadedFile.new(dir + file, "image/#{type}"))
      i.viewable = product.master
      i.save
    end
  end

  def change_image(product, dir, file)
    product.images.delete_all
    add_image(product, dir, file)
  end

  def set_load_code(row)
    if row[22].nil?
      nil
    else
      load_code = Spree::TireLoadCode.find_by_name(row[22])
      if load_code.nil?
        raise "Este Indice de Carga no existe #{row[22]}"
      else
        return load_code.id
      end
    end
  end

  def set_position(row)
    if row[24].nil?
      nil
    else
      case row[24]
        when "F"
          1
        when "R"
          2
        else
          3
      end
    end
  end

  def set_rf(row)
    if row[25].nil?
      nil
    else
      @tubes.index(row[25]) + 1
    end
  end

end
