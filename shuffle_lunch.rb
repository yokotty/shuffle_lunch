require 'csv'
require 'pp'
require 'date'

module ShuffleLunch

  CSV_PATH = 'shuffle_lunch_members.csv'.freeze
  MEMBER_COUNT_PER_GROUP = 5.freeze

  class << self
    def start
      members = generate_members_from_csv

      # 1グループの人数をランチグループを生成
      group_count = members.count / MEMBER_COUNT_PER_GROUP
      lunch_groups = Array.new(group_count) {
        LunchGroup.new(MEMBER_COUNT_PER_GROUP, MEMBER_COUNT_PER_GROUP + 1)
      }

      # グループにメンバーを振り分け
      members.each do |member|
        enable_lunch_groups =
          lunch_groups.reject { |group|
            group.enable_day_of_week_after_add(member).empty?
          }.shuffle
        raise '参加できるグループがありません' if enable_lunch_groups.empty?

        # すべてのグループが最低人数を満たすことを優先
        enable_lunch_groups.sort_by { |group|
          [ group.is_over_min_members ? 1 : 0,
            group.same_department_pairs_count_after_add(member)
          ]
        }.each { |group|
          break if group.add(member)
        }
      end

      lunch_groups.each.with_index(1) do |lunch_group, i|
        puts "====== シャッフルランチ#{i}組 ======"
        lunch_group.output_summary
      end
    end

    private

    def generate_members_from_csv
      members = []
      CSV.foreach(CSV_PATH, headers: true) do |row|
        members << Member.new(row)
      end

      # 部署ごとの人数を集計
      department_members = {}
      members.each do |member|
        member.departments.each do |department|
          department_members[department] = department_members[department].to_i + 1
        end
      end

      # 参加可能な曜日が少ない順 → 同部署メンバーが多い順でソートする
      # （制約が多い人を先にグループに配置した方がシャッフルの柔軟性が高くなるため）
      members.sort_by! do |member|
        [ member.enable_day_of_week.count,
          member.departments.sum {|department| department_members[department] }
        ]
      end
    end
  end
end

class Member
  attr_reader :id, :slack_id, :departments, :joined_date,
              :every_weekday, :monday, :tuesday, :wednesday, :thursday, :friday

  def initialize(attributes)
    @id = attributes['id']
    @slack_id = attributes['slack_id']
    @departments = attributes['department']
                    .split(/\s*[\r\n|\r|\n|]\s*/)
    @joined_date = Date.parse(attributes['joined_date'])

    @every_weekday = attributes['every_weekday'] == '1'
    %w(monday tuesday wednesday thursday friday).each do |key|
      flag = attributes[key] == '1' || every_weekday
      instance_variable_set("@#{key}", flag)
    end
  end

  def enable_day_of_week
    %i(monday tuesday wednesday thursday friday).select { |day| self.send(day) }
  end

  def same_department?(member)
    !(member.departments & departments).empty?
  end
end

class LunchGroup
  attr_reader :members, :max_count, :min_count

  DAY_OF_WEEK = {
    monday: '月曜日', tuesday: '火曜日', wednesday: '水曜日',
    thursday: '木曜日', friday: '金曜日'
  }.freeze

  def initialize(min_count, max_count)
    @min_count = min_count
    @max_count = max_count
    @members = []
  end

  # メンバーを追加
  def add(member)
    return false if members.count >= max_count || enable_day_of_week_after_add(member).empty?
    members << member
    true
  end

  # 同一部署所属ペア数
  def same_department_pairs
    members.combination(2).each_with_object([]) do |(member1, member2), array|
      array << [member1, member2] if member1.same_department?(member2)
    end
  end

  # メンバー追加後の同一部署所属ペア数
  def same_department_pairs_count_after_add(new_member)
    same_department_pairs.count +
      members.count {|member| member.same_department?(new_member) }
  end

  # 開催可能な曜日
  def enable_day_of_week
    result = DAY_OF_WEEK.dup.keys
    members.each { |member| result = result & member.enable_day_of_week }
    result
  end

  # メンバー追加後の開催可能な曜日
  def enable_day_of_week_after_add(member)
    enable_day_of_week & member.enable_day_of_week
  end

  # 最低人数以上のメンバーがいるか
  def is_over_min_members
    members.count >= min_count
  end

  # 結果出力
  def output_summary
    puts enable_day_of_week.map {|key| DAY_OF_WEEK[key] }.join('・')
    if same_department_pairs.count > 0
      puts "※ 同じ部署に所属している組み合わせが #{same_department_pairs.count} 組あります"
    end
    puts "#{member_slack_ids.join(' ')}\n"
  end

  private

  def member_slack_ids
    members.map(&:slack_id)
  end
end

ShuffleLunch.start
