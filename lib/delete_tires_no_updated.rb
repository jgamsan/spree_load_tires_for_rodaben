class DeleteTiresNoUpdated
  def initialize
    @delete_in_gane = 0
    @delete_in_eurotyre = 0
    @total_eurotyre = 0
    @total_gane = 0
    I18n.locale = 'es'
  end

  def run
    delete_tires
    send_mail
  end

  def delete_tires
    @delete_in_eurotyre = Spree::Product.where('updated_at < ? and supplier_id = ?', (Date.yesterday - 1), 2027)
    @total_eurotyre = @delete_in_eurotyre.count
    @delete_in_eurotyre.destroy_all
    @delete_in_gane = Spree::Product.where('updated_at < ? and supplier_id = ?', (Date.yesterday - 1), 1045)
    @total_gane = @delete_in_gane.count
    @delete_in_gane.destroy_all
  end

  def send_mail
    begin
      Spree::NotifyMailer.report_deleted_tires(@total_gane, @total_eurotyre).deliver
    rescue Exception => e
      logger.error("#{e.class.name}: #{e.message}")
      logger.error(e.backtrace * "\n")
    end
  end

end
