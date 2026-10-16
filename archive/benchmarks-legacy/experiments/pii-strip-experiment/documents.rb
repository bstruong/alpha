# frozen_string_literal: true

# Synthetic document generator with ground-truth PII manifest.
#
# Every person, address, phone, email and identifier below is INVENTED for this
# experiment. Emails use RFC-2606 reserved domains (example.com/.org), phone
# numbers use reserved ranges (555-01xx in the US), and the SSN-shaped values use
# the 900-series which is never issued. Nothing here refers to a real person.
#
# Each document carries a :tier —
#   :obvious — PII in clearly-labelled, conventionally-formatted form
#   :tricky  — PII that is unambiguously present but harder to spot: a person named
#              only through a role/relationship, a non-US phone format, an address
#              embedded mid-sentence with no label, an indirect/possessive name
#              reference, or a date of birth expressed as an age plus a reference date
#
# :pii is the exact ground truth: what was planted, typed, with the literal span.

module Documents
  TYPES = %w[name email phone address ssn dob].freeze

  ALL = [
    # ───────────────────────────── OBVIOUS ─────────────────────────────
    {
      id: "obv-01", tier: :obvious,
      text: <<~TEXT,
        Hi team,

        Quick follow-up on the Q3 vendor review. Contact Jane Doe at
        jane.doe@example.com if you need the signed copy of the addendum —
        she has the only countersigned original.

        Thanks,
        Ops
      TEXT
      pii: [
        { type: "name",  text: "Jane Doe" },
        { type: "email", text: "jane.doe@example.com" }
      ]
    },
    {
      id: "obv-02", tier: :obvious,
      text: <<~TEXT,
        MEMO — Facilities

        The badge reader on the third floor is failing intermittently. Marcus Webb
        is coordinating with the vendor; reach him on 555-0142 during business
        hours. Please do not prop the door open in the meantime.
      TEXT
      pii: [
        { type: "name",  text: "Marcus Webb" },
        { type: "phone", text: "555-0142" }
      ]
    },
    {
      id: "obv-03", tier: :obvious,
      text: <<~TEXT,
        Case note — intake

        Client: Ellen Prosser
        SSN: 900-58-1147
        Status: documents received, pending verification.

        Nothing further required from the client at this stage.
      TEXT
      pii: [
        { type: "name", text: "Ellen Prosser" },
        { type: "ssn",  text: "900-58-1147" }
      ]
    },
    {
      id: "obv-04", tier: :obvious,
      text: <<~TEXT,
        Shipping confirmation

        Recipient: Daniel Okafor
        Address: 1847 Larkspur Lane, Apt 3B, Fremont, CA 94539

        Your order shipped this morning and should arrive within three business
        days. No signature is required on delivery.
      TEXT
      pii: [
        { type: "name",    text: "Daniel Okafor" },
        { type: "address", text: "1847 Larkspur Lane, Apt 3B, Fremont, CA 94539" }
      ]
    },
    {
      id: "obv-05", tier: :obvious,
      text: <<~TEXT,
        Benefits enrolment record

        Employee: Sofia Renaldi
        Date of birth: 04/17/1986
        Plan tier: standard, employee only.

        Enrolment closes at the end of the month.
      TEXT
      pii: [
        { type: "name", text: "Sofia Renaldi" },
        { type: "dob",  text: "04/17/1986" }
      ]
    },
    {
      id: "obv-06", tier: :obvious,
      text: <<~TEXT,
        Subject: handover while I'm out

        I'm on leave next week. Tomas Lindqvist is covering the release train —
        email tomas.lindqvist@example.org or call 555-0177 if anything blocks.
        He has full access to the deploy keys.
      TEXT
      pii: [
        { type: "name",  text: "Tomas Lindqvist" },
        { type: "email", text: "tomas.lindqvist@example.org" },
        { type: "phone", text: "555-0177" }
      ]
    },
    {
      id: "obv-07", tier: :obvious,
      text: <<~TEXT,
        Contractor record — update

        Name: Priya Raghunathan
        Email: p.raghunathan@example.com
        Home address: 22 Kestrel Court, Bellingham, WA 98225

        Insurance certificate expires in November; renewal reminder set.
      TEXT
      pii: [
        { type: "name",    text: "Priya Raghunathan" },
        { type: "email",   text: "p.raghunathan@example.com" },
        { type: "address", text: "22 Kestrel Court, Bellingham, WA 98225" }
      ]
    },

    # ───────────────────────────── TRICKY ──────────────────────────────
    {
      # Person identified only through role + relationship, then named in apposition.
      id: "trk-01", tier: :tricky,
      text: <<~TEXT,
        Sorry for the short notice — my daughter's teacher, Mrs. Alvarez, called
        about the field trip paperwork and I had to take it. I'll be twenty minutes
        late to the standup. Start without me and I'll catch up from the notes.
      TEXT
      pii: [
        { type: "name", text: "Mrs. Alvarez" }
      ]
    },
    {
      # Non-US phone format, spelled with country code and spaces.
      id: "trk-02", tier: :tricky,
      text: <<~TEXT,
        The London office finally got back to us about the audit window. Their
        switchboard is +44 20 7946 0958 — ask for the compliance desk, not
        reception, or you'll get bounced around for twenty minutes.
      TEXT
      pii: [
        { type: "phone", text: "+44 20 7946 0958" }
      ]
    },
    {
      # Address embedded mid-sentence, no "Address:" label, no line of its own.
      id: "trk-03", tier: :tricky,
      text: <<~TEXT,
        We walked the site yesterday. The unit at 6014 Halstead Avenue, Unit 7,
        Portland, OR 97213 is in better shape than the listing photos suggest,
        though the roof will need attention before winter. Recommend proceeding
        to a formal inspection.
      TEXT
      pii: [
        { type: "address", text: "6014 Halstead Avenue, Unit 7, Portland, OR 97213" }
      ]
    },
    {
      # Name reachable only through a possessive chain — the person of interest is
      # the brother, named once, indirectly.
      id: "trk-04", tier: :tricky,
      text: <<~TEXT,
        Following up on the referral: Nadia's brother Arun Sethi is the one who
        actually holds the licence, not Nadia. Any paperwork needs his signature.
        I've asked her to pass along the forms this week.
      TEXT
      pii: [
        { type: "name", text: "Arun Sethi" },
        { type: "name", text: "Nadia" }
      ]
    },
    {
      # DOB expressed as an age relative to a stated reference date.
      id: "trk-05", tier: :tricky,
      text: <<~TEXT,
        Note for the file: the applicant mentioned during the 12 March 2024
        interview that he had turned 41 the previous week. That puts him just
        outside the early-career band for this programme, so route the
        application to the standard queue.
      TEXT
      pii: [
        { type: "dob", text: "turned 41 the previous week" }
      ]
    },
    {
      # Email in prose mid-sentence, lowercase, no "Email:" label, plus a name
      # given surname-first in a list context.
      id: "trk-06", tier: :tricky,
      text: <<~TEXT,
        Reordering the on-call list this quarter. Whitfield, Grace takes the first
        rotation; anything urgent should go to g.whitfield@example.org rather than
        the shared inbox, which nobody watches overnight.
      TEXT
      pii: [
        { type: "name",  text: "Whitfield, Grace" },
        { type: "email", text: "g.whitfield@example.org" }
      ]
    },
    {
      # International address in non-US ordering, mid-paragraph, plus a name that
      # appears only as a signature-style sign-off.
      id: "trk-07", tier: :tricky,
      text: <<~TEXT,
        The parts were misrouted again. They should go to Flat 4, 18 Wentworth
        Road, Sheffield S7 1TR, United Kingdom — not the depot. Third time this
        has happened this quarter and the courier keeps blaming the label.

        — H. Okonkwo
      TEXT
      pii: [
        { type: "address", text: "Flat 4, 18 Wentworth Road, Sheffield S7 1TR, United Kingdom" },
        { type: "name",    text: "H. Okonkwo" }
      ]
    }
  ].freeze

  def self.all = ALL
  def self.by_tier(tier) = ALL.select { it[:tier] == tier }
  def self.ground_truth_count = ALL.sum { it[:pii].size }
end

if __FILE__ == $PROGRAM_NAME
  require "json"
  puts JSON.pretty_generate(
    documents: Documents.all.size,
    obvious: Documents.by_tier(:obvious).size,
    tricky: Documents.by_tier(:tricky).size,
    ground_truth_items: Documents.ground_truth_count,
    by_type: Documents.all.flat_map { it[:pii] }.group_by { it[:type] }.transform_values(&:size)
  )
end
