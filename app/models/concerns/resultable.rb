# frozen_string_literal: true

require 'active_support/concern'

module Resultable
  extend ActiveSupport::Concern
  include ResultMethods

  included do
    # NOTE: We use cached values instead of belongs_to to improve performances.
    belongs_to :online_competition
    validates_presence_of :online_competition

    belongs_to :event
    validates_presence_of :event

    belongs_to :format
    validates_presence_of :format

    # Define cached stuff with the same name as the associations for validation
    def event
      Event.c_find(event_id)
    end

    def format
      Format.c_find(format_id)
    end

    validate :validate_each_solve, if: :event
    def validate_each_solve
      solve_times.each_with_index do |solve_time, i|
        unless solve_time.valid?
          errors.add(:"value#{i + 1}", solve_time.errors.full_messages.join(" "))
        end
      end
    end

    validate :validate_solve_count, if: :event
    def validate_solve_count
      errors.add(:base, invalid_solve_count_reason) if invalid_solve_count_reason
    end

    validate :validate_average
    def validate_average
      return if average_is_not_computable_reason

      correct_average = compute_correct_average
      errors.add(:average, "should be #{correct_average}") if correct_average != average
    end

    validate :validate_best, if: :event
    def validate_best
      correct_best = compute_correct_best
      errors.add(:best, "should be #{correct_best}") if correct_best != best
    end
  end

  def invalid_solve_count_reason
    return "Invalid format" unless format
    return "All solves cannot be DNS/skipped." if solve_times.all? { |s| s.dns? || s.skipped? }

    unless solve_times.drop_while(&:unskipped?).all?(&:skipped?)
      return "Skipped solves must all come at the end."
    end

    unskipped_count = solve_times.count(&:unskipped?)
    # NOTE: for AFS online, no combined round
    if unskipped_count != format.expected_solve_count
      return "Expected #{hlp.pluralize(format.expected_solve_count, 'solve')}, but found #{unskipped_count}."
    end
  end

  def average_is_not_computable_reason
    # To compute the average, we need to have a valid number of solves,
    # and we need to know what event we are dealing with (because
    # 333fm is computed differently than other events).
    event ? invalid_solve_count_reason : "Event needed to compute average"
  end

  def should_compute_average?
    # Average of 5 and Mean of 3 rounds should definitely attempt to compute the average (the average
    # may still be empty because of combined rounds).
    # Best of 3 is weird. We actually do want to populate the average column for best of 3 with:
    #  - 333fm was changed from allowing best of 3 (and disallowing mean of 3) to allowing mean of 3 (and disallowing best of 3).
    #    See "Relevant regulations changes" below.
    #    With this change in format, the Board decided to compute means for all
    #    the old best of 3 rounds, and assign mean records to them.
    #    However, we could not change the format of the rounds, as that would have affected rankings
    #    in past competitions, so the rounds remain as best of 3, but with an average computed.
    #  - 333ft has a similar story to 333fm. It also changed from allowing best of 3
    #    (and disallowing mean of 3) to allowing mean of 3 (and disallowing best
    #    of 3). See "Relevant regulations changes" below.
    #  - 333bf is quite a special case. At competitions, competitors are ranked according to best of 3, but
    #    the WCA awards records on both single and mean of 3.
    #    See https://www.worldcubeassociation.org/regulations/#9b3b.

    # Relevant regulations changes:
    #  - August 28, 2012 (beginning of the regulations on github): https://github.com/thewca/wca-regulations/commit/0c7f3e0501970c84178d914cd41a0d488ad3fac1
    #    - 333ft introduced with legal formats "123a".
    #  - September 9, 2012: https://github.com/thewca/wca-regulations/commit/6e5c44f0e397b735549923ff538846d3c4387dd4
    #    - 333ft legal formats changed from "123a" to "123m".
    #  - December 7, 2013: https://github.com/thewca/wca-regulations/commit/dc182c84e2ef60aeba37f5af896bd67f4c459575
    #    - 333fm legal formats changed from "123" to "123m".
    #  - December 9, 2013: https://github.com/thewca/wca-regulations/issues/109 and https://github.com/thewca/wca-regulations/commit/80ebf04e3ed0752df8047f4428277bf186f374c2
    #    - All events that allow "mean of 3" no longer allow "best of 3".
    format_id == "a" || format_id == "m" || (format_id == "3" && %w(333ft 333fm 333bf 444bf 555bf).include?(event_id))
  end

  def compute_correct_best
    best_solve = sorted_solves.first
    best_solve ? best_solve.wca_value : 0
  end

  def compute_correct_average
    if average_is_not_computable_reason || missed_combined_round_cutoff? || !should_compute_average?
      0
    else
      if counting_solve_times.any?(&:incomplete?)
        SolveTime::DNF_VALUE
      elsif event_id == "333fm"
        sum_moves = counting_solve_times.sum(&:move_count).to_f
        (100 * sum_moves / counting_solve_times.length).round
      else
        # Cast at least one of the operands to float
        sum_centis = counting_solve_times.sum(&:time_centiseconds).to_f
        raw_average = sum_centis / counting_solve_times.length
        # Round the result.
        # If the average is above 10 minutes, round it to the nearest second as per
        # https://www.worldcubeassociation.org/regulations/#9f2
        raw_average > 60_000 ? raw_average.round(-2) : raw_average.round
      end
    end
  end

  def to_solve_time(field)
    SolveTime.new(event_id, field, send(field))
  end

  def to_s(field)
    to_solve_time(field).clock_format
  end

  def hlp
    ActionController::Base.helpers
  end
end
