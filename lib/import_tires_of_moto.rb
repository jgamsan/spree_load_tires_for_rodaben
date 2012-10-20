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
    @inc_precio = 9.95
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
    CSV.foreach(File.join(@directory, @file)) do |row|
      begin
        if Spree::Variant.existe_moto_tire(row[1]) #buscar por SKU
          variante = Spree::Variant.search_moto_tire(row[1])
          cost_price = (row[12].to_f * 1.21).round(2)
          price = (row[12].to_f * 1.21 + @inc_precio).round(2)
          variante.update_attributes(
              :price => price,
              :cost_price => price - @inc_precio,
              :price_in_offert => price
          )
          @updated += 1
          puts "Actualizado #{row[2]}" unless Rails.env.production?
        else
          i += 1
          # crear uno nuevo
          product = Spree::Product.new
          product.name = row[2]
          product.permalink = row[2].downcase.gsub(/\s+/, '-').gsub(/[^a-zA-Z0-9_]+/, '-')
          product.sku = row[1]
          product.available_on = hoy - 1.day
          cost_price = (row[12].to_f * 1.21).round(2)
          price = (row[12].to_f * 1.21 + @inc_precio).round(2)
          product.price = price
          product.cost_price = price - @inc_precio
          product.price_in_offert = price
          product.show_in_offert = false
          product.supplier_id = 2028
          product.tire_width_id = set_width(row)
          product.tire_serial_id = set_serial(row)
          product.tire_innertube_id = set_innertube(row)
          product.tire_speed_code_id = set_speed_code(row)
          product.taxons << Spree::Taxon.find(9) #cargar categoria
          product.taxons << Spree::Taxon.find(set_brand(row)) #cargar marca
          if product.save!
            puts "Creado articulo #{row[2]}" unless Rails.env.production?
            j += 1
          end
          v = Spree::Variant.find_by_product_id(product.id)
          v.update_column(:count_on_hand, 6)
          add_image(product, @default_wd, row[14])
          v = nil
          product = nil
          @created += 1
        end
      rescue Exception => e
        no_leidos << [row[1], row[2], row[7], row[8], row[12], row[18], row[20], row[22], row[24], e]
        next
      end
    end
    unless no_leidos.empty?
      headers_row = ["SKU", "Nombre", "Categoria", "Marca", "Precio", "Marca", "Modelo", "Oferta", "Precio", "Stock"]
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
    ancho = Spree::TireWidth.find_by_name(row[18])
    if ancho.nil?
      raise "Este ancho no existe #{row[18]}"
    else
      return ancho.id
    end
  end

  def set_serial(row)
    serie = Spree::TireSerial.find_by_name(row[20])
    if serie.nil?
      raise "Este perfil no existe #{row[20]}"
    else
      return serie.id
    end
  end

  def set_innertube(row)
    llanta = Spree::TireInnertube.find_by_name(row[22])
    if llanta.nil?
      raise "Esta llanta no existe #{row[22]}"
    else
      return llanta.id
    end
  end

  def set_speed_code(row)
    if row[24].nil?
      nil
    else
      vel = Spree::TireSpeedCode.find_by_name(row[24])
      if vel.nil?
        raise "Este Indice Velocidad no existe #{row[24]}"
      else
        return vel.id
      end
    end
  end

  def set_brand(row)
    brand = Spree::Taxon.where(:parent_id => 2, :name => row[8]).first #@taxons.fetch(row[5])
    if brand.nil?
      raise "Marca #{row[8]} no esta registrada"
    else
      return brand.id
    end
  end

  def add_image(product, dir, file)
    type = file.split(".").last
    i = Spree::Image.new(:attachment => Rack::Test::UploadedFile.new(dir + file, "image/#{type}"))
    i.viewable = product.master
    i.save
  end


end
