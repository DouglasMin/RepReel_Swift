import Foundation
import Testing
@testable import ReelsKit

/// Fixtures are copied from the response examples in `docs/API_SPECIFICATION.md`.
@Suite("Program decoding")
struct ProgramDecodingTests {

    @Test("Decodes a program whose program_data omits the duplicated scalars")
    func decodesProgramResponse() throws {
        let json = """
        {
          "program_id": "che-dan-sil-ppl-routine-part2",
          "creator": "이정훈 | 운동루틴",
          "title": "체단실 루틴 2탄",
          "split_type": "PPL (Push/Pull/Legs)",
          "cycle_frequency": "6일 운동 1일 휴식",
          "program_data": {
            "days": [{
              "day_number": 1,
              "day_title": "Day 1: 푸쉬",
              "day_focus": "가슴/어깨/삼두",
              "target_muscle_groups": ["가슴", "어깨"],
              "exercise_groups": [{
                "category": "Main Compound (메인 복합 다관절 운동)",
                "target_region": "가슴 (상부 대흉근)",
                "exercises": [{
                  "exercise_id": "bench_press",
                  "canonical_name_ko": "벤치프레스",
                  "canonical_name_en": "Bench Press",
                  "equipment": "Barbell (바벨)",
                  "primary_muscle": "대흉근",
                  "secondary_muscles": ["삼두", "전면 삼각근"],
                  "is_main_lift": true,
                  "volume": {
                    "min_sets": 5, "max_sets": 5,
                    "min_reps": 8, "max_reps": 10,
                    "rep_type": "Reps Range (반복 횟수 범위)",
                    "rest_seconds": 180,
                    "rpe_target": 8.5
                  },
                  "guide": {
                    "form_cues": ["견갑골을 후인하강"],
                    "common_mistakes_to_avoid": ["엉덩이 들림"],
                    "tempo_notes": null
                  }
                }]
              }]
            }],
            "progression": { "overload_strategy": "더블 프로그레션", "frequency_schedule": "주 6회" },
            "audit": {
              "confidence_score": 0.98,
              "sets_ambiguous": false,
              "weight_missing": true,
              "rest_missing": false,
              "user_action_items": ["벤치프레스 중량 입력 필요"],
              "audit_notes": "영상에 중량 언급 없음"
            }
          }
        }
        """.data(using: .utf8)!

        let program = try JSONDecoder().decode(WorkoutProgramResponse.self, from: json)

        #expect(program.programId == "che-dan-sil-ppl-routine-part2")
        #expect(program.splitType == .ppl)
        #expect(program.days.count == 1)
        #expect(program.days[0].exerciseGroups[0].category == .mainCompound)

        let exercise = try #require(program.days.first?.exerciseGroups.first?.exercises.first)
        #expect(exercise.equipment == .dumbbell || exercise.equipment == .barbell)
        #expect(exercise.volume.volumeDisplayString == "5세트 × 8-10회")
        #expect(exercise.volume.restDisplayString == "휴식 3분")
        #expect(program.audit?.needsReview == true)
    }

    @Test("Decodes the program list rows, which carry no program_data")
    func decodesProgramList() throws {
        let json = """
        {
          "count": 1,
          "programs": [{
            "program_id": "che-dan-sil-ppl-routine-part2",
            "title": "체단실 루틴 2탄",
            "creator": "이정훈 | 운동루틴",
            "split_type": "PPL (Push/Pull/Legs)",
            "created_at": 1771977014
          }]
        }
        """.data(using: .utf8)!

        let list = try JSONDecoder().decode(ProgramListResponse.self, from: json)
        #expect(list.programs.count == 1)
        #expect(list.programs[0].createdDate != nil)
    }

    @Test("Decodes an accepted ingestion and a completed job")
    func decodesJobLifecycle() throws {
        let accepted = """
        {"success": true, "job_id": "job_a1", "reel_id": "DccqEKJPPqR",
         "status": "PROCESSING", "status_url": "/jobs/job_a1"}
        """.data(using: .utf8)!
        let ingest = try JSONDecoder().decode(IngestResponse.self, from: accepted)
        #expect(ingest.status == .processing)
        #expect(ingest.status.isTerminal == false)

        let done = """
        {"job_id": "job_a1", "reel_id": "DccqEKJPPqR", "status": "COMPLETED",
         "program_id": "che-dan-sil-ppl-routine-part2", "confidence_score": 0.98,
         "created_at": 1771977000, "updated_at": 1771977014}
        """.data(using: .utf8)!
        let job = try JSONDecoder().decode(JobStatusResponse.self, from: done)
        #expect(job.status.isTerminal)
        #expect(job.programId == "che-dan-sil-ppl-routine-part2")
    }

    @Test("Round-trips a session log through snake_case keys")
    func encodesSessionLog() throws {
        let session = WorkoutSessionLog(
            programId: "p1",
            dayNumber: 1,
            loggedAt: 1771979000,
            durationSeconds: 3600,
            completedExercises: [
                ExecutedExerciseLog(
                    exerciseId: "bench_press",
                    exerciseName: "벤치프레스",
                    sets: [LoggedSet(setNumber: 1, weightKg: 80, reps: 10, rpe: 8, completed: true)]
                )
            ],
            sessionNotes: "컨디션 좋았음."
        )

        let data = try JSONEncoder().encode(session)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["program_id"] as? String == "p1")
        #expect(object["duration_seconds"] as? Int == 3600)
        let exercises = try #require(object["completed_exercises"] as? [[String: Any]])
        let sets = try #require(exercises[0]["sets"] as? [[String: Any]])
        #expect(sets[0]["weight_kg"] as? Double == 80)
    }

    @Test("Correctly normalizes Push day exercises so accessory/isolation are not lumped into Main")
    func normalizesExerciseGroups() throws {
        let json = """
        {
          "day_number": 1,
          "day_title": "Day 1: 푸쉬",
          "exercise_groups": [{
            "category": "Main Compound (메인 복합 다관절 운동)",
            "target_region": "가슴",
            "exercises": [
              {
                "exercise_id": "bench_press",
                "canonical_name_ko": "바벨 벤치프레스",
                "equipment": "Barbell (바벨)",
                "primary_muscle": "대흉근",
                "is_main_lift": true,
                "volume": { "min_sets": 4, "min_reps": 8 }
              },
              {
                "exercise_id": "arnold_press",
                "canonical_name_ko": "아놀드 프레스",
                "equipment": "Dumbbell (덤벨)",
                "primary_muscle": "전면 삼각근",
                "is_main_lift": false,
                "volume": { "min_sets": 3, "min_reps": 12 }
              },
              {
                "exercise_id": "side_lateral_raise",
                "canonical_name_ko": "사이드 래터럴 레이즈",
                "equipment": "Dumbbell (덤벨)",
                "primary_muscle": "측면 삼각근",
                "is_main_lift": false,
                "volume": { "min_sets": 4, "min_reps": 15 }
              },
              {
                "exercise_id": "bent_over_lateral_raise",
                "canonical_name_ko": "벤트오버 래터럴 레이즈",
                "equipment": "Dumbbell (덤벨)",
                "primary_muscle": "후면 삼각근",
                "is_main_lift": false,
                "volume": { "min_sets": 4, "min_reps": 15 }
              }
            ]
          }]
        }
        """.data(using: .utf8)!

        let day = try JSONDecoder().decode(WorkoutDay.self, from: json)
        let normalized = day.normalizedExerciseGroups

        // Should be normalized into 4 distinct groups by category and muscle
        #expect(normalized.count == 4)

        #expect(normalized[0].category == .mainCompound)
        #expect(normalized[0].targetRegion == "대흉근")
        #expect(normalized[0].exercises.first?.canonicalNameKo == "바벨 벤치프레스")

        #expect(normalized[1].category == .accessory)
        #expect(normalized[1].targetRegion == "전면 삼각근")
        #expect(normalized[1].exercises.first?.canonicalNameKo == "아놀드 프레스")

        #expect(normalized[2].category == .isolation)
        #expect(normalized[2].targetRegion == "측면 삼각근")
        #expect(normalized[2].exercises.first?.canonicalNameKo == "사이드 래터럴 레이즈")

        #expect(normalized[3].category == .isolation)
        #expect(normalized[3].targetRegion == "후면 삼각근")
        #expect(normalized[3].exercises.first?.canonicalNameKo == "벤트오버 래터럴 레이즈")
    }
}
