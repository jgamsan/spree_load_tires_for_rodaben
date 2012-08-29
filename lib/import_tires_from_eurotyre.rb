# encoding: UTF-8
require 'csv'

class ImportTiresFromEurotyre

  def initialize()
    @agent = Mechanize.new
    @final = "#{Rails.root}/vendor/products/listado-neumaticos-eurotyre.csv"
    @send_file = "#{Rails.root}/vendor/products/listado-neumaticos-no-incorporados-eurotyre.csv"
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
    t = Spree::Taxon.where(:parent_id => 2).order("id").map {|x| [x.name, x.id]}.flatten
    @marcas = Spree::Taxon.where(:parent_id => 2).order("id").map {|x| x.name}
    @taxons = Hash[*t]
    @marcas_eurotyre = CSV.read("#{Rails.root}/vendor/products/listado-marcas-eurotyre.csv").map {|x| x[0]}
    I18n.locale = 'es'
  end

  def run
    if login
      read_from_eurotyre
      export_to_csv
      load_from_csv
      delete_no_updated
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
    form = page.form('search')
    select_list = form.field_with(:name => "u_marca")
    @marcas_eurotyre.each do |marca|
      puts "descargando #{marca}"
      select_list.value = [marca]
      page2 = form.submit
      #puts marca
      page2.search(".//table[@id='product_list']//tbody//tr").each do |d|
        for i in 0..9
          ruedas << d.search(".//td")[i].text
        end
      end
      for i in 0..(ruedas.count/10) - 1
        @total << [ruedas[i*10], ruedas[i*10 + 1], ruedas[i*10 + 2],
                  ruedas[i*10 + 3], ruedas[i*10 + 4], ruedas[i*10 + 5],
                  ruedas[i*10 + 6], ruedas[i*10 + 7], ruedas[i*10 + 8], ruedas[i*10 + 9]]
        @readed += 1
      end
      ruedas.clear
    end
  end

  def export_to_csv
    CSV.open(@final, "wb") do |row|
      @total.each do |element|
        #[ancho, perfil, llanta, ic, iv, marca, modelo, oferta, precio, stock]
        row << element
      end
    end
  end

  def load_from_csv
    #[ancho, perfil, llanta, ic, iv, marca, modelo, oferta, precio, stock]
    result = []
    fallos = []
    no_leidos = []
    i = j = 0
    hoy = Date.today
    productos = Spree::Product.where(:supplier_id => 2).map {|x| x.name}.flatten
    CSV.foreach(@final) do |row|
      begin
        if productos.include?(row[6]) # producto existe
          articulo = Spree::Product.find_by_name(row[6])
          articulo.update_column(:show_in_offert, row[7].empty? ? false : true)
          variante = Spree::Variant.find_by_product_id(articulo.id)
          variante.update_attributes(
              :count_on_hand => row[9],
              :cost_price => (row[7].empty? ? row[8] : row[7]) * 1.05,
              :price => row[8] * 1.05,
              :price_in_offert => (row[7].empty? ? row[8] : row[7]) * 1.05 #falta de poner el precio de venta segun cliente
          )
          @updated += 1
          puts "Actualizado #{row[6]}"                            # actualizar los precios
        else
          i += 1
          # crear uno nuevo
          product = Spree::Product.new
          product.name = row[6]
          product.permalink = row[6].downcase.gsub(/\s+/, '-').gsub(/[^a-zA-Z0-9_]+/, '-')
          product.sku = hoy.strftime("%y%m%d%H%m") + i.to_s
          product.available_on = hoy - 1.day
          product.price = row[8] * 1.05 #falta de poner el precio de venta segun cliente
          product.cost_price = (row[7].empty? ? row[8] : row[7]) * 1.05
          product.price_in_offert = (row[7].empty? ? row[8] : row[7]) * 1.05
          product.show_in_offert = row[7].empty? ? false : true
          product.supplier_id = 2027
          product.tire_width_id = set_width(row)
          product.tire_serial_id = set_serial(row)
          product.tire_innertube_id = set_innertube(row)
          product.tire_speed_code_id = set_speed_code(row)
          product.tire_rf = false
          product.tire_gr = false
          product.tire_season = 2
          product.taxons << Spree::Taxon.find(6) #cargar categoria
          product.taxons << Spree::Taxon.find(set_brand(row)) #cargar marca
          if product.save!
            puts "Creado articulo #{row[6]}"
            j += 1
          end
          v = Spree::Variant.find_by_product_id(product.id)
          v.update_column(:count_on_hand, row[9])
          add_image(product, @default_wd, @default_img)
          v = nil
          product = nil
          @created += 1
        end
      rescue Exception => e
        #puts e
        fallos << [row[6], e]
        no_leidos << [row[0], row[1], row[2], row[3], row[4], row[5]]
        next
      end
    end
    unless fallos.empty?
      CSV.open("#{Rails.root}/vendor/products/listado-fallos-eurotyre.csv", "wb") do |row|
        fallos.each do |element|
          row << element
        end
      end
    end
    unless no_leidos.empty?
      headers_row = ["Ancho", "Perfil", "Llanta", "IC", "IV", "Marca", "Modelo", "Oferta", "Precio", "Stock"]
      CSV.open(@send_file, "wb", {headers: headers_row, write_headers: true}) do |row|
        no_leidos.each do |element|
          row << element
        end
      end
    end
  end

  def set_width(row)
    #[ancho, perfil, llanta, ic, iv, marca, modelo, oferta, precio, stock]
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
    vel = Spree::TireSpeedCode.find_by_name(row[4])]
    if vel.nil?
      raise "Este IV no existe #{row[4]}"
    else
      return vel.id
    end
  end

  def set_brand(row)
    @taxons.fetch(row[5])
  end

  def delete_no_updated
    nuevos = []
    total = Spree::Product.where(:support_id => 2027)
    almacenados = total.map {|x| x.name}
    CSV.foreach(@final) do |row|
      nuevos << row[0]
    end
    eliminar = almacenados - nuevos
    eliminar.each do |element|
      t = Spree::Product.find_by_name(element)
      unless t.nil?
        t.destroy
        @deleted += 1
      end
    end
  end

  def send_mail
    begin
      Spree::NotifyMailer.report_notification(@readed, @updated, @deleted, @created).deliver
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
