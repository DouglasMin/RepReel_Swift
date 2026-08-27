#if DEBUG
import Foundation
import ReelsKit

/// Canned backend responses so the UI can be exercised without a live API —
/// used by `#Preview` blocks and by demo mode (`-demo` launch argument).
///
/// The JSON deliberately mirrors the shapes in `docs/API_SPECIFICATION.md`; if a
/// preview stops decoding, the fixture and the real contract have drifted.
enum PreviewFixtures {

    /// Routes by path suffix, same trick the tests use.
    struct FixtureTransport: HTTPTransport {
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let path = request.url?.path ?? ""
            let body: String

            switch true {
            case path.hasSuffix("/programs"):
                body = programList
            case path.contains("/programs/"):
                body = programDetail
            case path.contains("/jobs/"):
                body = processingJob
            case path.hasSuffix("/reels"):
                body = acceptedIngest
            default:
                body = #"{"success":true}"#
            }

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (Data(body.utf8), response)
        }
    }

    /// A fully populated environment on a throwaway App Group suite, so demo
    /// state never mixes with the real one.
    @MainActor
    static func environment(withPendingJob: Bool = true) -> AppEnvironment {
        let config = AppConfig(
            apiHost: "demo.local",
            appSecret: "demo",
            appGroupID: "group.demo.reelsworkout",
            developmentUserEmail: "demo@example.com"
        )
        // `init(config:transport:)` only throws if the App Group is unusable.
        let environment = try! AppEnvironment(config: config, transport: FixtureTransport())

        environment.pendingJobs.removeAll()
        if withPendingJob {
            environment.pendingJobs.append(
                PendingJob(
                    jobId: "job_demo_1",
                    reelURL: "https://www.instagram.com/reel/DccqEKJPPqR/"
                )
            )
        }
        return environment
    }

    // MARK: - Response bodies

    static let acceptedIngest = #"""
    {"success":true,"job_id":"job_demo_1","reel_id":"DccqEKJPPqR","status":"PROCESSING"}
    """#

    static let processingJob = #"""
    {"job_id":"job_demo_1","reel_id":"DccqEKJPPqR","status":"PROCESSING","created_at":1771977000}
    """#

    static let programList = #"""
    {
      "count": 3,
      "programs": [
        {
          "program_id": "che-dan-sil-ppl-routine-part2",
          "title": "체단실 루틴 2탄",
          "creator": "이정훈 | 운동루틴",
          "split_type": "PPL (Push/Pull/Legs)",
          "created_at": 1771977014
        },
        {
          "program_id": "upper-lower-4day",
          "title": "주 4회 상하체 분할 (초중급자용)",
          "creator": "핏블리 FITVELY",
          "split_type": "Upper/Lower (상체/하체)",
          "created_at": 1771890614
        },
        {
          "program_id": "home-fullbody-nogym",
          "title": "헬스장 없이 전신 루틴",
          "creator": "김강민 홈트",
          "split_type": "Full Body (무분할/전신)",
          "created_at": 1771804214
        }
      ]
    }
    """#

    static let programDetail = #"""
    {
      "program_id": "che-dan-sil-ppl-routine-part2",
      "reel_id": "DccqEKJPPqR",
      "creator": "이정훈 | 운동루틴",
      "title": "체단실 루틴 2탄",
      "split_type": "PPL (Push/Pull/Legs)",
      "cycle_frequency": "6일 운동 1일 휴식",
      "overview": "푸쉬-풀-레그 3분할을 2회전 돌리는 6일 루틴입니다.",
      "created_at": 1771977014,
      "program_data": {
        "days": [
          {
            "day_number": 1,
            "day_title": "Day 1: 푸쉬",
            "day_focus": "가슴 · 어깨 · 삼두",
            "target_muscle_groups": ["대흉근", "삼각근", "상완삼두근"],
            "exercise_groups": [
              {
                "category": "Main Compound (메인 복합 다관절 운동)",
                "target_region": "가슴 (중부 대흉근)",
                "exercises": [
                  {
                    "exercise_id": "bench_press",
                    "canonical_name_ko": "바벨 벤치프레스",
                    "canonical_name_en": "Barbell Bench Press",
                    "equipment": "Barbell (바벨)",
                    "primary_muscle": "대흉근",
                    "secondary_muscles": ["상완삼두근", "전면 삼각근"],
                    "is_main_lift": true,
                    "volume": {
                      "min_sets": 5, "max_sets": 5,
                      "min_reps": 8, "max_reps": 10,
                      "rep_type": "Reps Range (반복 횟수 범위)",
                      "rest_seconds": 180,
                      "rpe_target": 8.5
                    },
                    "guide": {
                      "form_cues": ["견갑골을 후인하강 시킨 상태를 유지", "바를 명치 방향으로 내리기"],
                      "common_mistakes_to_avoid": ["엉덩이가 벤치에서 들리는 것"],
                      "tempo_notes": "2초 내리고 1초 폭발적으로"
                    }
                  },
                  {
                    "exercise_id": "incline_db_press",
                    "canonical_name_ko": "인클라인 덤벨 프레스",
                    "canonical_name_en": "Incline Dumbbell Press",
                    "equipment": "Dumbbell (덤벨)",
                    "primary_muscle": "상부 대흉근",
                    "secondary_muscles": ["전면 삼각근"],
                    "is_main_lift": false,
                    "volume": {
                      "min_sets": 4, "max_sets": 4,
                      "min_reps": 10, "max_reps": 12,
                      "rep_type": "Reps Range (반복 횟수 범위)",
                      "rest_seconds": 120,
                      "rpe_target": 8.0
                    },
                    "guide": {
                      "form_cues": ["벤치 각도는 30도"],
                      "common_mistakes_to_avoid": ["덤벨을 맞부딪히며 반동 주기"],
                      "tempo_notes": null
                    }
                  }
                ]
              },
              {
                "category": "Accessory (보조 복합/단일 운동)",
                "target_region": "어깨 (측면 삼각근)",
                "exercises": [
                  {
                    "exercise_id": "ohp",
                    "canonical_name_ko": "오버헤드 프레스",
                    "canonical_name_en": "Overhead Press",
                    "equipment": "Barbell (바벨)",
                    "primary_muscle": "전면 삼각근",
                    "secondary_muscles": ["상완삼두근", "승모근"],
                    "is_main_lift": false,
                    "volume": {
                      "min_sets": 4, "max_sets": 5,
                      "min_reps": 6, "max_reps": 8,
                      "rep_type": "Reps Range (반복 횟수 범위)",
                      "rest_seconds": 150,
                      "rpe_target": 8.0
                    },
                    "guide": {
                      "form_cues": ["복압을 유지하고 갈비뼈가 열리지 않게"],
                      "common_mistakes_to_avoid": ["허리를 과도하게 젖히기"],
                      "tempo_notes": null
                    }
                  }
                ]
              },
              {
                "category": "Isolation (고립/레이즈 운동)",
                "target_region": "어깨 (측면 삼각근)",
                "exercises": [
                  {
                    "exercise_id": "lateral_raise",
                    "canonical_name_ko": "사이드 레터럴 레이즈",
                    "canonical_name_en": "Side Lateral Raise",
                    "equipment": "Dumbbell (덤벨)",
                    "primary_muscle": "측면 삼각근",
                    "secondary_muscles": [],
                    "is_main_lift": false,
                    "volume": {
                      "min_sets": 4, "max_sets": 4,
                      "min_reps": 15, "max_reps": 20,
                      "rep_type": "Reps Range (반복 횟수 범위)",
                      "rest_seconds": 60,
                      "weight_guidance": "가벼운 중량으로 자극 위주",
                      "rpe_target": 9.0
                    },
                    "guide": {
                      "form_cues": ["새끼손가락이 살짝 위를 향하게"],
                      "common_mistakes_to_avoid": ["반동으로 들어올리기"],
                      "tempo_notes": null
                    }
                  },
                  {
                    "exercise_id": "cable_pushdown",
                    "canonical_name_ko": "케이블 푸시다운",
                    "canonical_name_en": "Cable Triceps Pushdown",
                    "equipment": "Cable (케이블)",
                    "primary_muscle": "상완삼두근",
                    "secondary_muscles": [],
                    "is_main_lift": false,
                    "volume": {
                      "min_sets": 3, "max_sets": 4,
                      "min_reps": 12, "max_reps": 15,
                      "rep_type": "Reps Range (반복 횟수 범위)",
                      "rest_seconds": 75,
                      "rpe_target": 8.5
                    },
                    "guide": {
                      "form_cues": ["팔꿈치를 몸통에 고정"],
                      "common_mistakes_to_avoid": ["어깨로 눌러 내리기"],
                      "tempo_notes": null
                    }
                  }
                ]
              }
            ]
          },
          {
            "day_number": 2,
            "day_title": "Day 2: 풀",
            "day_focus": "등 · 이두",
            "target_muscle_groups": ["광배근", "승모근", "상완이두근"],
            "exercise_groups": [
              {
                "category": "Main Compound (메인 복합 다관절 운동)",
                "target_region": "등 (광배근)",
                "exercises": [
                  {
                    "exercise_id": "deadlift",
                    "canonical_name_ko": "컨벤셔널 데드리프트",
                    "canonical_name_en": "Conventional Deadlift",
                    "equipment": "Barbell (바벨)",
                    "primary_muscle": "척추기립근",
                    "secondary_muscles": ["광배근", "둔근", "햄스트링"],
                    "is_main_lift": true,
                    "volume": {
                      "min_sets": 4, "max_sets": 4,
                      "min_reps": 5, "max_reps": 5,
                      "rep_type": "Fixed Reps (고정 횟수)",
                      "rest_seconds": 240,
                      "rpe_target": 9.0
                    },
                    "guide": {
                      "form_cues": ["바를 정강이에 붙여서 끌어올리기"],
                      "common_mistakes_to_avoid": ["허리가 말린 채로 시작"],
                      "tempo_notes": null
                    }
                  },
                  {
                    "exercise_id": "pullup",
                    "canonical_name_ko": "풀업",
                    "canonical_name_en": "Pull-up",
                    "equipment": "Bodyweight (맨몸)",
                    "primary_muscle": "광배근",
                    "secondary_muscles": ["상완이두근"],
                    "is_main_lift": false,
                    "volume": {
                      "min_sets": 4, "max_sets": 4,
                      "min_reps": 8,
                      "rep_type": "To Failure (실패 지점까지)",
                      "rest_seconds": 120
                    },
                    "guide": {
                      "form_cues": ["가슴을 봉 쪽으로 밀어올린다는 느낌"],
                      "common_mistakes_to_avoid": ["팔로만 당기기"],
                      "tempo_notes": null
                    }
                  }
                ]
              },
              {
                "category": "Core / Finisher (코어 및 마무리 운동)",
                "target_region": "복부",
                "exercises": [
                  {
                    "exercise_id": "hanging_leg_raise",
                    "canonical_name_ko": "행잉 레그레이즈",
                    "canonical_name_en": "Hanging Leg Raise",
                    "equipment": "Bodyweight (맨몸)",
                    "primary_muscle": "복직근 하부",
                    "secondary_muscles": ["장요근"],
                    "is_main_lift": false,
                    "volume": {
                      "min_sets": 3, "max_sets": 3,
                      "min_reps": 12, "max_reps": 15,
                      "rep_type": "Reps Range (반복 횟수 범위)",
                      "rest_seconds": 60
                    },
                    "guide": {
                      "form_cues": ["골반을 말아올리며 수축"],
                      "common_mistakes_to_avoid": ["다리만 흔들기"],
                      "tempo_notes": null
                    }
                  }
                ]
              }
            ]
          }
        ],
        "progression": {
          "overload_strategy": "더블 프로그레션 — 목표 반복 수 상단을 모든 세트에서 채우면 다음 주에 2.5kg 증량합니다.",
          "frequency_schedule": "6일 운동 후 1일 완전 휴식",
          "recovery_guidance": "수면 7시간 이상, 체중 1kg당 단백질 1.6g 이상 섭취를 권장합니다."
        },
        "audit": {
          "confidence_score": 0.82,
          "sets_ambiguous": false,
          "weight_missing": true,
          "rest_missing": false,
          "user_action_items": [
            "벤치프레스 시작 중량을 직접 입력해 주세요 (영상에 언급 없음)",
            "사이드 레터럴 레이즈 세트 수가 영상에서 불명확합니다"
          ],
          "audit_notes": "영상 자막에 중량 정보가 없어 중량 필드를 비워 두었습니다."
        }
      }
    }
    """#
}
#endif
