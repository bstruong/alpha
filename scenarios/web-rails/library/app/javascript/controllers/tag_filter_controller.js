import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "form"]

  filter() {
    // Title search input is required; tag-only filter must still submit.
    this.formTarget.setAttribute("novalidate", "novalidate")
    this.formTarget.requestSubmit()
  }
}
