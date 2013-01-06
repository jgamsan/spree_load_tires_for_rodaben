# encoding: UTF-8
require 'csv'

class ImportTiresFromEurotyre

  def initialize()
    @agent = Mechanize.new
    @directory = "#{Rails.root}/vendor/products"
    @final = "listado-neumaticos-eurotyre.csv"
    @send_file = "listado-neumaticos-no-incorporados-eurotyre.csv"
    @image_wd = "#{Rails.root}/vendor/products/images/"
    @default_wd = "#{Rails.root}/app/assets/images/"
    @default_img = "default.png"
    @total = []
    @no_leidos = []
    @horario = []
    @created = 0
    @updated = 0
    @deleted = 0
    @readed = 0
    @inc_precio = 9.95
    @num_columns = 12
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
    str = "http://www.eurotyre.pt/shop/shop"
    page = @agent.get(str)
    ruedas = []
    eco = []
    form = page.form('search')
    select_list = form.field_with(:name => "u_marca")
    list = form.field_with(:name => "u_marca").options
    list.each do |marca|
      select_list.value = [marca]
      puts "Leyendo #{marca}" unless Rails.env.production?
      page2 = form.submit
      page2.search(".//table[@id='product_list']//tbody//tr").each do |d|
        for i in 0..(@num_columns - 1)
          ruedas << d.search(".//td")[i].text
        end
        d.search(".//td[@class='etiqueta']").each do |p|
          eco << p.search(".//span").text
        end
      end
      for i in 0..((ruedas.count/@num_columns) - 1)
        @total << [ruedas[i*@num_columns], ruedas[i*@num_columns + 1], ruedas[i*@num_columns + 2],
                  ruedas[i*@num_columns + 3], ruedas[i*@num_columns + 4], ruedas[i*@num_columns + 5],
                  ruedas[i*@num_columns + 6], ruedas[i*@num_columns + 7], ruedas[i*@num_columns + 8],
                  ruedas[i*@num_columns + 9].gsub(/\D/, "."), ruedas[i*@num_columns + 10], ruedas[i*@num_columns + 11], eco[i]]
        @readed += 1
      end
      ruedas.clear
      eco.clear
    end
  end

  def export_to_csv
    CSV.open(File.join(@directory, @final), "wb") do |row|
      @total.each do |element|
        #[ancho, perfil, llanta, ic, iv, marca, modelo, foto, oferta, precio, stock, Barcelona]
        row << element
      end
    end
  end

  def load_from_csv
    #[ancho, perfil, llanta, ic, iv, marca, modelo, foto, oferta, precio, stock, Barcelona]
    result = []
    fallos = []
    no_leidos = []
    i = j = 0
    hoy = Date.today
    productos = Spree::Product.where(:supplier_id => 2027).map {|x| x.name}.flatten
    CSV.foreach(File.join(@directory, @final)) do |row|
      begin
        if Spree::Variant.existe_tire?(row[6], row[0], row[1], row[2], row[4]) # producto existe
          variante = Spree::Variant.search_tire(row[6], row[0], row[1], row[2], row[4]).first
          #articulo = Spree::Product.find(variante.product_id)
          variante.product.update_column(:show_in_offert, row[8].empty? ? false : true)
          if row[7].empty?
            cost_price = (row[9].to_f * 1.21).round(2)
            price = (row[9].to_f * 1.21 + @inc_precio).round(2)
          else
            cost_price = (row[8].to_f * 1.21).round(2)
            price = (row[8].to_f * 1.21 + @inc_precio).round(2)
          end
          #variante.update_column(:cost_price, cost_price)
          #variante.update_column(:price, price)
          variante.update_attributes(
              :price => price,
              :cost_price => cost_price,
              :count_on_hand => row[10],
              :price_in_offert => (row[9].to_f * 1.21 + @inc_precio).round(2)
          )
          @updated += 1
          puts "Actualizado #{row[6]}" unless Rails.env.production?
        else
          i += 1
          # crear uno nuevo
          product = Spree::Product.new
          product.name = row[6]
          product.permalink = row[6].downcase.gsub(/\s+/, '-').gsub(/[^a-zA-Z0-9_]+/, '-')
          product.sku = hoy.strftime("%y%m%d%H%m") + i.to_s
          product.available_on = hoy - 1.day
          if row[8].empty?
            cost_price = (row[9].to_f * 1.21).round(1)
            price = (row[9].to_f * 1.21 + @inc_precio).round(1)
          else
            cost_price = (row[8].to_f * 1.21).round(1)
            price = (row[8].to_f * 1.21 + @inc_precio).round(1)
          end
          product.price = price
          product.cost_price = cost_price
          product.price_in_offert = (row[9].to_f * 1.21 + @inc_precio).round(1)
          product.show_in_offert = row[8].empty? ? false : true
          product.supplier_id = 2027
          product.tire_width_id = set_width(row)
          product.tire_serial_id = set_serial(row)
          product.tire_innertube_id = set_innertube(row)
          product.tire_speed_code_id = set_speed_code(row)
          product.tire_rf = false
          product.tire_gr = false
          product.tire_season = 2
          product.tire_fuel_consumption_id = set_fuel_consumption(row)
          product.tire_wet_grip_id = set_wet_grip(row)
          product.tire_rolling_noise_db = set_rolling_noise_db(row)
          product.tire_rolling_noise_wave = set_rolling_noise_wave(row)
          product.tire_green_rate_id = 2
          product.tire_load_code_id = set_load_code(row)
          product.tax_category_id = 1
          product.shipping_category_id = 1
          product.taxons << Spree::Taxon.find(4) #cargar categoria
          product.taxons << Spree::Taxon.find(set_brand(row)) #cargar marca
          if product.save!
            puts "Creado articulo #{row[6]}" unless Rails.env.production?
            j += 1
          end
          #v = Spree::Variant.find_by_product_id(product.id)
          product.master.update_attributes(:count_on_hand => row[10])
          add_image(product, @default_wd, @default_img)
          v = nil
          product = nil
          @created += 1
        end
      rescue Exception => e
        no_leidos << [row[0], row[1], row[2], row[3], row[4], row[5], row[6], row[8], row[9], row[10], e]
        next
      end
    end
    unless no_leidos.empty?
      headers_row = ["Ancho", "Perfil", "Llanta", "IC", "IV", "Marca", "Modelo", "Oferta", "Precio", "Stock"]
      CSV.open(File.join(@directory, @send_file), "wb", {headers: headers_row, write_headers: true}) do |row|
        no_leidos.each do |element|
          row << element
        end
      end
    end
  end

  def set_width(row)
    #[ancho, perfil, llanta, ic, iv, marca, modelo, oferta, precio, PVP, stock]
    ancho = Spree::TireWidth.find_by_name(row[0])
    if ancho.nil?
      raise "Este ancho no existe #{row[0]}"
    else
      return ancho.id
    end
  end

  def set_serial(row)
    serie = Spree::TireSerial.find_by_name(row[1])
    if serie.nil?
      raise "Este perfil no existe #{row[1]}"
    else
      return serie.id
    end
  end

  def set_innertube(row)
    llanta = Spree::TireInnertube.find_by_name(row[2])
    if llanta.nil?
      raise "Esta llanta no existe #{row[2]}"
    else
      return llanta.id
    end
  end

  def set_speed_code(row)
    if row[4].nil?
      nil
    else
      vel = Spree::TireSpeedCode.find_by_name(row[4])
      if vel.nil?
        raise "Este Indice Velocidad no existe #{row[4]}"
      else
        return vel.id
      end
    end
  end

  def set_load_code(row)
    load_code = row[3]
    if load_code =~ %r{(\d+)(?:/|:)(\d+)}
      g = [$1,$2]
      result =g[0]
    else
      result = load_code
    end
    load = Spree::TireLoadCode.find_by_name(result)
    if load.nil?
      raise "Este Indice de carga no existe #{load_code}"
    else
      return load.id
    end
  end

  def set_fuel_consumption(row)
    if row[12].nil
      nil
    else
      row[12] =~ %r{([A-Z])([A-Z])(\d)(\d{2})}
      eco = [$1,$2,$3,$4]
      fuel = Spree::TireFuelConsumption.find_by_name(eco[0])
      fuel.id
    end
  end

  def set_wet_grip(row)
    if row[12].nil
      nil
    else
      row[12] =~ %r{([A-Z])([A-Z])(\d)(\d{2})}
      eco = [$1,$2,$3,$4]
      wet = Spree::TireWetGrip.find_by_name(eco[1])
      wet.id
    end
  end

  def set_rolling_noise_db(row)
    if row[12].nil
      nil
    else
      row[12] =~ %r{([A-Z])([A-Z])(\d)(\d{2})}
      eco = [$1,$2,$3,$4]
      noise_db = eco[3].to_i
    end
  end

  def set_rolling_noise_wave(row)
    if row[12].nil
      nil
    else
      row[12] =~ %r{([A-Z])([A-Z])(\d)(\d{2})}
      eco = [$1,$2,$3,$4]
      noise_wave = eco[2].to_i
    end
  end

  def set_brand(row)
    if row[5].nil?
      raise "Marca #{row[5]} no esta registrada"
    else
      if row[5].include?(" ")
        marca = row[5].split.join('-').downcase
      else
        marca = row[5].downcase
      end
      brand = Spree::Taxon.find_by_permalink("marcas/#{marca}")
      return brand.id
    end
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
      logger.error("#{e.class.name}: #{e.message}")
      logger.error(e.backtrace * "\n")
    end
  end

  def add_image(product, dir, file)
    type = file.split(".").last
    i = Spree::Image.new(:attachment => Rack::Test::UploadedFile.new(dir + file, "image/#{type}"))
    i.viewable = product.master
    i.save
  end
end
