import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "open", "close", "return"]

  open() {
    this.dialogTarget.showModal()
    this.closeTarget.focus()
  }

  close() {
    this.dialogTarget.close()
    this.returnTarget.focus()
  }
}
