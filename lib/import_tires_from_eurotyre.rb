# encoding: UTF-8
require 'csv'

class ImportTiresFromEurotyre

  def initialize
    @agent = Mechanize.new
    @directory = "#{Rails.root}/vendor/products"
    @final = 'listado-neumaticos-eurotyre.csv'
    @send_file = 'listado-neumaticos-no-incorporados-eurotyre.csv'
    @name = Time.now.strftime('%Y%m%d%H%M') + 'EURO' + '.log'
    @logger = Logger.new(File.join(@directory, @name))
    @image_wd = "#{Rails.root}/vendor/products/images/"
    @default_wd = "#{Rails.root}/app/assets/images/"
    @default_img = 'default.png'
    @total = []
    @no_leidos = []
    @horario = []
    @created = 0
    @updated = 0
    @deleted = 0
    @readed = 0
    @inc_precio = 9.95
    @num_columns = 12
    @green_rate = Spree::TireGreenRate.find_by_cat("B").id
    @shipping_category = Spree::ShippingCategory.where("name like '%Automovil%'").first.id
    @tax_category = Spree::TaxCategory.where("name like '%Ecotasa%'").first.id
    @fuel_options = Hash['A', '-14-55', 'B', '-13-33', 'C', '-13-11', 'D', '-13+11', 'E', '-13+33', 'F', '-13+55', 'G', '-13+77']
    @wet_options = Hash['A', '+103-53', 'B', '+103-31', 'C', '+103-9', 'D', '+103+13', 'E', '+103+35', 'F', '+103+56', 'G', '+103+78']
    @headers_row = %w(Ancho Perfil Llanta IC IV Marca Modelo Oferta Precio Stock)
    #t = Spree::Taxon.where(:parent_id => 2).order("id").map {|x| [x.name, x.id]}.flatten
    #@marcas = Spree::Taxon.where(:parent_id => 2).order("id").map {|x| x.name}
    #@taxons = Hash[*t]
    #@marcas_eurotyre = CSV.read("#{Rails.root}/vendor/products/listado-marcas-eurotyre.csv").map {|x| x[0]}
    I18n.locale = 'es'
  end

  def run
    if login
      read_from_eurotyre
      export_to_csv
      load_from_csv
      send_mail
    end
  end

  def login
    page = @agent.get('http://www.eurotyre.pt/shop/login')
    eurotyre_form = page.form('loginform')
    eurotyre_form.username = 'nrodaben@yahoo.es'
    eurotyre_form.passwd = 'jose1222'
    eurotyre_form.submit
  end

  def read_from_eurotyre
    str = 'http://www.eurotyre.pt/shop/shop'
    page = @agent.get(str)
    ruedas = []
    eco = []
    form = page.form('search')
    select_list = form.field_with(:name => 'u_marca')
    list = form.field_with(:name => 'u_marca').options
    list.each do |marca|
      select_list.value = [marca]
      puts "Leyendo #{marca}" unless Rails.env.production?
      page2 = form.submit
      page2.search(".//table[@id='product_list']//tbody//tr").each do |d|
        for i in 0..(@num_columns - 1)
          ruedas << d.search('.//td')[i].text
        end
        d.search(".//td[@class='etiqueta']").each do |p|
          eco << p.search('.//span').text
        end
      end
      for i in 0..((ruedas.count/@num_columns) - 1)
        @total << [ruedas[i*@num_columns], ruedas[i*@num_columns + 1], ruedas[i*@num_columns + 2],
                  ruedas[i*@num_columns + 3], ruedas[i*@num_columns + 4], ruedas[i*@num_columns + 5],
                  ruedas[i*@num_columns + 6], ruedas[i*@num_columns + 7], ruedas[i*@num_columns + 8],
                  ruedas[i*@num_columns + 9], ruedas[i*@num_columns + 10], ruedas[i*@num_columns + 11], eco[i]]
        @readed += 1
      end
      ruedas.clear
      eco.clear
    end
  end

  def export_to_csv
    CSV.open(File.join(@directory, @final), 'wb') do |row|
      @total.each do |element|
        #[ancho, perfil, llanta, ic, iv, marca, modelo, foto, oferta, precio, stock, Barcelona]
        row << element
      end
    end
  end

  def load_from_csv
    #[ancho, perfil, llanta, ic, iv, marca, modelo, foto, oferta, precio, stock, Barcelona]
    no_leidos = []
    i = j = 0
    hoy = Date.today
    CSV.foreach(File.join(@directory, @final)) do |row|
      begin
        if Spree::Variant.existe_tire?(row[6], row[0], row[1], row[2], row[4]) # producto existe
          variante = Spree::Variant.search_tire(row[6], row[0], row[1], row[2], row[4]).first
          variante.product.update_column(:show_in_offert, row[8].nil? ? false : true)
          if row[8].nil?
            cost_price = (row[9].delete(' €').to_f * 1.21).round(2)
            price = (row[9].delete(' €').to_f * 1.21 + @inc_precio).round(2)
          else
            cost_price = (row[8].delete(' €').to_f * 1.21).round(2)
            price = (row[8].delete(' €').to_f * 1.21 + @inc_precio).round(2)
          end
          variante.update_attributes(
              :price => price,
              :cost_price => cost_price,
              :count_on_hand => row[10],
              :price_in_offert => (row[9].delete(' €').to_f * 1.21 + @inc_precio).round(2)
          )
          if variante.images.empty?
            add_image(variante, @default_wd, @default_img)
          end
          @updated += 1
          if Rails.env.production?
            @logger.info "Actualizado #{row[6]}"
          else
            puts "Actualizado #{row[6]}".white.on_blue
          end
        else
          i += 1
          product = Spree::Product.new
          product.name = row[6].to_s.match(/^\d+$/).nil? ? row[6] : row[6] + "-#{row[0]}/#{row[1]}R#{row[2]}"
          product.permalink = row[6].downcase.gsub(/\s+/, '-').gsub(/[^a-zA-Z0-9_]+/, '-')
          product.sku = hoy.strftime('%y%m%d%H%m') + i.to_s
          product.available_on = hoy - 1.day
          product.show_in_offert = row[8].nil? ? false : true
          product.supplier_id = 2027

          variant = Spree::Variant.new

          if row[8].nil?
            cost_price = (row[9].delete(' €').to_f * 1.21).round(1)
            price = (row[9].delete(' €').to_f * 1.21 + @inc_precio).round(1)
          else
            cost_price = (row[8].delete(' €').to_f * 1.21).round(1)
            price = (row[8].delete(' €').to_f * 1.21 + @inc_precio).round(1)
          end

          variant.price = product.price = price
          variant.cost_price = cost_price
          variant.price_in_offert = (row[9].delete(' €').to_f * 1.21 + @inc_precio).round(1)

          variant.tire_width_id = set_width(row)
          variant.tire_serial_id = set_serial(row)
          variant.tire_innertube_id = set_innertube(row)
          variant.tire_speed_code_id = set_speed_code(row)
          variant.tire_rf = false
          variant.tire_gr = false
          variant.tire_season = 2
          if row[12].blank?
            variant.tire_fuel_consumption_id = nil
            variant.tire_wet_grip_id = nil
            variant.tire_rolling_noise_db = nil
            variant.tire_rolling_noise_wave = nil
          else
            variant.tire_fuel_consumption_id = set_fuel_consumption(row)
            variant.tire_wet_grip_id = set_wet_grip(row)
            variant.tire_rolling_noise_db = set_rolling_noise_db(row)
            variant.tire_rolling_noise_wave = set_rolling_noise_wave(row)
          end

          variant.tire_green_rate_id = @green_rate
          variant.tire_load_code_id = set_load_code(row)
          variant.count_on_hand = row[10]
          product.tax_category_id = @tax_category
          product.shipping_category_id = @shipping_category
          product.taxons << Spree::Taxon.find(4) #cargar categoria
          product.taxons << Spree::Taxon.find(set_brand(row)) #cargar marca

          product.master = variant

          if product.save!
            if Rails.env.production?
              @logger.info "Creado articulo #{row[6]}"
            else
              puts "Creado articulo #{row[6]}".white.on_blue
            end
            j += 1
          end
          add_image(variant, @default_wd, @default_img)
          modify_cee_label_image(variant, row) unless row[12].nil?
          variant = nil
          product = nil
          @created += 1
        end
      rescue Exception => e
        puts "error en carga de datos #{row[6]}".white.on_red unless Rails.env.production?
        no_leidos << [row[0], row[1], row[2], row[3], row[4], row[5], row[6], row[8], row[9], row[10], e]
        @logger.info("#{row[6]}, #{row[0]}, #{row[1]}, #{row[2]}, #{row[3]}")
        @logger.error("#{e.class.name}: #{e.message}")
        @logger.error(e.backtrace * "\n")
        @logger.info '=' * 50
        next
      end
    end
    unless no_leidos.empty?
      CSV.open(File.join(@directory, @send_file), 'wb', {headers: @headers_row, write_headers: true}) do |row|
        no_leidos.each do |element|
          row << element
        end
      end
    end
  end

  def set_width(row)
    #[ancho, perfil, llanta, ic, iv, marca, modelo, oferta, precio, PVP, stock]
    return nil if row[0] == '0'
    ancho = Spree::TireWidth.find_by_name(row[0])
    ancho.nil? ? raise("Este ancho no existe #{row[0]}") : ancho.id
  end

  def set_serial(row)
    return nil if row[1] == '0'
    serie = Spree::TireSerial.find_by_name(row[1])
    serie.nil? ? raise("Este perfil no existe #{row[1]}") : serie.id
  end

  def set_innertube(row)
    return nil if row[2] == '0'
    llanta = Spree::TireInnertube.find_by_name(row[2])
    llanta.nil? ? raise("Esta llanta no existe #{row[2]}") : llanta.id
  end

  def set_speed_code(row)
    return nil if row[4].nil?
    vel = Spree::TireSpeedCode.find_by_name(row[4])
    vel.nil? ? raise("Este Indice Velocidad no existe #{row[4]}") : vel.id
  end

  def set_load_code(row)
    return nil if row[3].nil?
    row[3] =~ %r{(\d{1,3})}
    g = [$1,$2]
    load = Spree::TireLoadCode.find_by_name(g[0])
    load.nil? ? raise("Este Indice de carga no existe #{load}") : load.id
  end

  def set_fuel_consumption(row)
    row[12] =~ %r{([A-Z])([A-Z])(\d)(\d{2})}
    eco = [$1,$2,$3,$4]
    fuel = Spree::TireFuelConsumption.find_by_name(eco[0])
    fuel.id
  end

  def set_wet_grip(row)
    row[12] =~ %r{([A-Z])([A-Z])(\d)(\d{2})}
    eco = [$1,$2,$3,$4]
    wet = Spree::TireWetGrip.find_by_name(eco[1])
    wet.id
  end

  def set_rolling_noise_db(row)
    row[12] =~ %r{([A-Z])([A-Z])(\d)(\d{2})}
    eco = [$1,$2,$3,$4]
    eco[3].to_i
  end

  def set_rolling_noise_wave(row)
    row[12] =~ %r{([A-Z])([A-Z])(\d)(\d{2})}
    eco = [$1,$2,$3,$4]
    eco[2].to_i
  end

  def set_brand(row)
    raise "Este neumatico no tiene Marca" if row[5].nil?
    marca = row[5].downcase.gsub(/\s+/, '-').gsub(/[^a-zA-Z0-9_]+/, '-')
    brand = Spree::Taxon.find_by_permalink("marcas/#{marca}")
    brand.nil? ? raise("Marca #{row[5]} no esta registrada") : brand.id
  end

  def read_file(file)
    nuevos = []
    CSV.foreach(file) do |row|
      nuevos << row[6]
    end
    return nuevos
  end

  def send_mail
    begin
      Spree::NotifyMailer.report_notification(@readed, @updated, @deleted, @created, @directory, @send_file, "EUROTYRE").deliver
    rescue Exception => e
      @logger.error("#{e.class.name}: #{e.message}")
      @logger.error(e.backtrace * "\n")
    end
  end

  def add_image(variant, dir, file)
    img = Spree::Image.new({:attachment => File.open(dir + file), :viewable => variant}, :without_protection => true)
    img.save!
    variant.images << img
  end

  def modify_cee_label_image(variant, row)
    imagen = variant.images.first
    fuel = variant.tire_fuel_consumption.name
    wet = variant.tire_wet_grip.name
    noise_db = variant.tire_rolling_noise_db
    noise_wave = variant.tire_rolling_noise_wave
    image = MiniMagick::Image.open(imagen.attachment.path(:ceelabel))
    result = image.composite(MiniMagick::Image.open("#{Rails.root}/app/assets/images/#{fuel.downcase}.png"), "png") do |c|
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
    result.write(imagen.attachment.path(:ceelabel))
    puts "modificada etiqueta CEE con #{row[12]}".white.on_blue unless Rails.env.production?
  end
end
