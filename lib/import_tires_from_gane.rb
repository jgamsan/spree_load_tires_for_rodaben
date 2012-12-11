# encoding: UTF-8
require 'csv'

class ImportTiresFromGane

  def initialize()
    @agent = Mechanize.new
    @directory = "#{Rails.root}/vendor/products"
    @final = "listado-neumaticos-gane.csv"
    @send_file = "listado-neumaticos-no-incorporados-gane.csv"
    #@file_old = "listado-gane-antiguo.csv"
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
    @tubes = %w(TL TT RU)
    t = Spree::Taxon.where(:parent_id => 2).order("id").map {|x| [x.name, x.id]}.flatten
    @marcas = Spree::Taxon.where(:parent_id => 2).order("id").map {|x| x.name}
    @taxons = Hash[*t]
    @error = ""
    @modificaciones = %w(GOODYEAR)
    @invierno = %w(WINTER SNOW RAIN)
    I18n.locale = 'es'
  end

  def run
    if login
      puts "Logueado en Gane correctamente"
      read_from_gane
      export_to_csv
      load_from_csv
      send_mail
    end
  end

  def read_from_gane
    str = "http://galaicoasturianadeneumaticos.distritok.com/sqlcommerce/disenos/plantilla1/seccion/Catalogo.jsp?idIdioma=&idTienda=50&cPath=61"
    sch = ".//table[@class='result']//tr//td[@class='result_right']//a[@title='Siguiente ']"
    links = []
    until str.empty?
      page = @agent.get(str)
      page.search(".//table[@class='tableBox_output']//tr").each do |d|
        ti = d.search("td[@width='900']//a")
        t = ti.text.strip
        l = ti.map {|x| x[:href]}
        r = d.search("td//span[@class='linCat']").map {|x| x.text}
        unless r.empty?
          if r[1] == "Consultar"
              p = k = pf = s = 0
          else
            s = r[0].to_s.strip
            p = r[1].to_s.delete("€").strip.gsub(/,/, '.').to_f
            k = r[2].to_s.delete("%").strip.gsub(/,/, '.').to_f
            pf = r[3].to_s.delete("€").strip.gsub(/,/, '.').to_f
            img = read_image(l) if Spree::Product.find_by_name(t).nil?
            puts "Leido #{t}" unless Rails.env.production? 
          end
        end
        @total << [t, s, p, k, pf, img]
        @readed += 1
      end
      links.clear
      page.search(sch).each do |link|
        links << link[:href]
      end
      links = links.uniq
      str = links[0].to_s
      #puts str
    end
  end

  def export_to_csv
    CSV.open(File.join(@directory, @final), "wb") do |row|
      @total.each do |element|
        #[nombre, stock, precio, descuento, precio final]
        row << element
      end
    end
  end

  def load_from_csv
    # [ancho, serie, llanta, vel, tube, marca, gr]
    result = []
    fallos = []
    no_leidos = []
    i = j = 0
    hoy = Date.today
    productos = Spree::Product.where(:supplier_id => 1045).map {|x| x.name}.flatten
    CSV.foreach(File.join(@directory, @final)) do |row|
      begin
        unless row[0].blank?
          if productos.include?(row[0]) # producto existe
            articulo = Spree::Product.find_by_name(row[0])
            articulo.update_column(:show_in_offert, row[3].to_f > 0 ? true : false)
            variante = Spree::Variant.find_by_product_id(articulo.id)
            cost_price = row[2].to_f * 1.21
            price = (row[4].to_f * 1.21 + @inc_precio).round(2)
#            variante.update_column(:cost_price, cost_price)
#            variante.update_column(:price, price)
            variante.update_attributes(
              :cost_price => cost_price,
              :price => price,
              :count_on_hand => set_stock(row[1]),
              :price_in_offert => (row[2].to_f * 1.21 + @inc_precio).round(2)
            )
            @updated += 1
            puts "Actualizado #{row[0]}" unless Rails.env.production?
          else
            result = read_format(row[0])
            i += 1
            # crear uno nuevo
            product = Spree::Product.new
            product.name = row[0]
            product.permalink = row[0].downcase.gsub(/\s+/, '-').gsub(/[^a-zA-Z0-9_]+/, '-')
            product.sku = hoy.strftime("%y%m%d%H%m") + i.to_s
            product.available_on = hoy - 1.day
            #product.count_on_hand = set_stock(row[1])
            product.price = (row[4].to_f * 1.21 + @inc_precio).round(1) #falta de poner el precio de venta segun cliente
            product.cost_price = row[4].to_f * 1.21
            product.price_in_offert = (row[2].to_f * 1.21 + @inc_precio).round(1)
            product.show_in_offert = row[3].to_f > 0 ? true : false
            product.supplier_id = 1045
            product.tire_width_id = set_width(result)
            product.tire_serial_id = set_serial(result)
            product.tire_innertube_id = set_innertube(result)
            product.tire_speed_code_id = set_speed_code(result)
            product.tire_rf = false
            product.tire_gr = result[6]
            product.tire_season = set_season(row[0])
            product.taxons << Spree::Taxon.find(result[6]) #cargar categoria
            product.taxons << Spree::Taxon.find(set_brand(result)) #cargar marca
            if product.save!
              puts "Creado articulo #{row[0]}" unless Rails.env.production?
              j += 1
            end
            #v = Spree::Variant.find_by_product_id(product.id)
            product.master.update_attributes(:count_on_hand => set_stock(row[1]))
            if row[5].nil?
              add_image(product, @default_wd, @default_img)
            else
              add_image(product, @image_wd, row[5])
            end
            v = nil
            product = nil
            @created += 1
          end
        end
      rescue Exception => e
        no_leidos << [row[0], row[1], row[2], row[3], row[4], row[5], e]
        next
      end
    end
    unless no_leidos.empty?
      headers_row = ["Nombre", "Stock", "Precio", "Descuento", "Precio Final", "Imagen", "Motivo"]
      CSV.open(File.join(@directory, @send_file), "wb") do |row|
        no_leidos.each do |element|
          row << element
        end
      end
    end
  end

  def read_file(file)
    nuevos = []
    CSV.foreach(file) do |row|
      nuevos << row[0]
    end
    nuevos
  end

  def send_mail
    begin
      Spree::NotifyMailer.report_notification(@readed, @updated, @deleted, @created, @directory, @send_file, "GANE").deliver
    rescue Exception => e
      logger.error("#{e.class.name}: #{e.message}")
      logger.error(e.backtrace * "\n")
    end
  end

  private

  def login
    login = '929'
    password = 'B36973667'
    direccion = 'http://galaicoasturianadeneumaticos.distritok.com/'
    page = @agent.get(direccion)
    gane_form = page.form('login')
    gane_form.login = login
    gane_form.password = password
    gane_form.submit
  end

  def read_format(rueda)
    rueda = rueda.to_s
    if rueda =~ %r{(\S+)(?:\s|:)(\D)(?:\s|:)(\S+)(?:\s|:)([TLRU]{2})(?:\s|:)(\S+)(?:\s|:)} #1
      g = [$1,$2,$3,$4,$5,$6]
      if g[0] =~ %r{(\d+)(?:/|:)(\d+)}
        ancho_nuevo = [$1,$2]
        ancho = ancho_nuevo[0]
        serie = ancho_nuevo[1]
      elsif g[0] =~ %r{(\d+)(?:[Xx]|:)(\S+)}
        ancho_nuevo = [$1,$2]
        ancho = ancho_nuevo[1]
      else
        ancho = g[0]
        serie = nil
      end
      llanta = g[2].scan(/\d+/)[0]
      tube = read_tube(g[3])
      vel = g[4]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, set_catalog(g)]
    elsif rueda =~ %r{(\S+)(?:\s|:)([TLRU]{2})(?:\s|:)} #3
      g = [$1,$2,$3,$4]
      if g[0] =~ %r{(\S+)(?:/|:)(\S+)(?:-|:)(\S+)}
        ancho_nuevo = [$1,$2,$3]
        if ancho_nuevo[0].to_i > 100
          ancho = ancho_nuevo[0]
          serie = ancho_nuevo[1]
          llanta = ancho_nuevo[2].scan(/\d+/)[0]
        else
          ancho = ancho_nuevo[1]
          llanta = ancho_nuevo[2].scan(/\d+/)[0]
          serie = nil
        end
      elsif g[0] =~ %r{(\S+)(?:-|:)(\S+)}
        h = [$1,$2]
        ancho = h[0]
        serie = nil
      end
      tube = g[1]
      vel = nil
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, 8]
    elsif rueda =~ %r{(\d+)(?:/|:)(\d+)(?:\s|:)(\D)(?:\s|:)(\S+)(?:\s|:)(\S+)(?:/|:)(\S+)} #11
      g = [$1,$2,$3,$4]
      if g[0] =~ %r{(\d+)(?:/|:)(\d+)}
        ancho_nuevo = [$1,$2]
        ancho = ancho_nuevo[0]
        serie = ancho_nuevo[1]
      else
        ancho = g[0]
        serie = nil
      end
      llanta = g[2].scan(/\d+/)[0]
      tube = nil
      vel = g[3]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, 6]
    elsif rueda =~ %r{(\d+)(?:\s|:)(\D)(?:\s|:)(\d+[A-Z])(?:\s|:)([TLRU]{2})(?:\s|:)(\S+)(?:\s|:)(\S+)} #13
      g = [$1,$2,$3,$4,$5,$6]
      ancho = g[0]
      serie = nil
      llanta = g[2]
      tube = g[3]
      vel = g[5]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, 6]
    elsif rueda =~ %r{(\S+)(?:\s|:)(\S+)(?:\s|:)(\S+)} #4
      g = [$1,$2,$3]
      if g[0] =~ %r{(\S+)(?:/|:)(\S+)(?:-|:)(\S+)}
        ancho_nuevo = [$1,$2,$3]
        if ancho_nuevo[0].to_i > 100
          ancho = ancho_nuevo[0]
          serie = ancho_nuevo[1]
          llanta = ancho_nuevo[2]
        else
          ancho = ancho_nuevo[1]
          llanta = ancho_nuevo[2]
          serie = nil
        end
      elsif g[0] =~ %r{(\d+)(?:[Xx]|:)(\d+)}
        ancho_nuevo = [$1,$2]
        ancho = ancho_nuevo[1]
        serie = nil
        llanta = nil
      elsif g[0] =~ %r{(\S+)(?:-|:)(\S+)}
        h = [$1,$2]
        ancho = h[0]
        serie = nil
      end
      vel = nil
      if g[1].include?("PR")
        vel = nil
      else
        vel = g[1]
      end
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, 6]
    else
      puts "No leido #{rueda}"
    end
  end

  def read_taxon(rueda)
   str = rueda.split
   if str.include?("GOODYEAR") || (str.include?("GOOD") & str.include?("YEAR"))
    inter = ["GOOD-YEAR"]
   else
    inter = str & @marcas
   end
   @taxons.fetch(inter[0])
   #@marcas.find_index(inter[0])
  end

  def read_tube(tube)
    if tube.nil?
      nil
    else
      @tubes.find_index(tube)
    end
  end

  def set_width(row)
    if row[0].nil?
      return nil
    else
      ancho = Spree::TireWidth.find_by_name(row[0])
      if ancho.nil?
        raise "Este ancho no existe #{row[0]}"
      else
        return ancho.id
      end
    end
  end

  def set_serial(row)
    if row[1].nil?
      return nil
    else
      serie = Spree::TireSerial.find_by_name(row[1])
      if serie.nil?
        raise "Este perfil no existe #{row[1]}"
      else
        return serie.id
      end
    end
  end

  def set_innertube(row)
    if row[2].nil?
      row[2]
    else
      llanta = Spree::TireInnertube.find_by_name(row[2])
      if llanta.nil?
        raise "Esta llanta no existe #{row[2]}"
      else
        return llanta.id
      end
    end
  end

  def set_speed_code(row)
    str = row[3]
    if str.nil?
      nil
    else
      if str =~ %r{(\S+)(?:/|:)(\S+)}
        vel_nueva = [$1,$2]
        vel = get_vel_code(vel_nueva[1])
      elsif str == "ZR"
        vel = str
      else
        vel = get_vel_code(str)
      end
      vel_final = Spree::TireSpeedCode.find_by_name(vel)
      if vel_final.nil?
        raise "Este Indice Velocidad no existe #{vel}"
      else
        return vel_final.id
      end
    end
  end

  def set_season(name)
    existe = 2
    @invierno.each do |element|
      if name.include?(element)
        existe = 1
      end
    end
    return existe
  end

  def set_brand(row)
    marca = row[5]
  end

  def set_stock(stock)
    if stock.include?("<")
      stock.delete("<").scan(/\d+/)[0].to_i - 1
    elsif stock.include?(">")
      stock.delete(">").scan(/\d+/)[0].to_i
    else
      stock.to_i
    end
  end

  def set_catalog(catalog)
    f1 = catalog[3].scan(/\D+/)[0]
    unless f1.nil?
      case f1
        when "C"
          7
        when "CP"
          9
        else
          6
      end
    end
  end

  def get_vel_code(str)
    if str.include?("A")
      str.scan(/[A]\d/)[0]
    else
      str.scan(/[A-Z]/)[0]
    end
  end

  def read_image(links)
    links.each do |ln|
      page1 = @agent.get(ln).search(".//table[@id='tablaFotograf']//tr")
      page1.each do |m|
        l1 = m.search("td//img[@id='imagenProducto']").map {|x| x[:src]}
        b = l1[0]
        d = File.basename(b)
        if d == "0_articulosinfoto.jpg"
          return nil
        else
          Net::HTTP.start("galaicoasturianadeneumaticos.distritok.com") { |http|
            resp = http.get(b)
            open(d, "wb") { |file|
              file.write(resp.body)
            }
          }
          FileUtils.mv(d, @image_wd)
          #puts "Descargada imagen #{d}"
          return d
        end
      end
    end
  end

  def add_image(product, dir, file)
    type = file.split(".").last
    i = Spree::Image.new(:attachment => Rack::Test::UploadedFile.new(dir + file, "image/#{type}"))
    i.viewable = product.master
    i.save
  end
end
