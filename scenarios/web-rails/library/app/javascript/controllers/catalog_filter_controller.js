import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["query", "item"]

  filter() {
    const needle = this.queryTarget.value.trim().toLowerCase()
    this.itemTargets.forEach((li) => {
      const name = (li.getAttribute("data-name") || "").toLowerCase()
      li.hidden = needle.length > 0 && !name.includes(needle)
    })
  }
}
